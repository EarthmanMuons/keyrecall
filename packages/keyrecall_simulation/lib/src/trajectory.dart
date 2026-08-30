import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

/// One slot of a simulated sitting, with everything a detector needs.
///
/// The whole trace rather than the chosen exercise, because most of what has
/// gone wrong was invisible in the choice and obvious in what it was chosen
/// over. Every hand-built census this repository has needed reconstructed
/// exactly this, and reconstructing it after the fact is how three separate
/// wrong diagnoses got made.
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

  /// The paced tempo for the chosen material and hand, before the attempt.
  final double pacedBefore;

  /// The tempo this hand had shown at this span on material it already owns,
  /// before the attempt, or zero when it had shown none.
  ///
  /// What an unseen scale can legitimately be met at, recorded at decision
  /// time because it is the input a later detector has to compare the chosen
  /// tempo against.
  final double transferableBefore;

  /// Materials whose hands-together prerequisite the scheduler considered
  /// satisfied this slot, whatever happened afterwards.
  ///
  /// Read from stage 2a's own verdict rather than reconstructed from
  /// outcomes. Readiness is the scheduler's notion, and a clock that starts
  /// when both hands have merely completed a material once may start earlier
  /// or later than production's, which puts every latency derived from it in
  /// doubt.
  final Set<String> handsTogetherReady;

  /// Materials for which a *fully eligible* hands-together candidate survived
  /// admission this slot.
  ///
  /// Fully eligible, and per material, because neither weaker reading says
  /// anything. Any surviving hands-together candidate is nearly always
  /// available: the catalog is wide, most of it is provisionally eligible on
  /// the hands-together prerequisite, and provisional candidates still survive
  /// admission and rank last. Counting those makes an availability metric read
  /// as though coordination work were on offer from the first slot, which was
  /// how a first measurement here concluded that hands together loses on
  /// ranking when it had never genuinely been offered.
  final Set<String> handsTogetherOffered;

  const TrajectorySlot({
    required this.index,
    required this.at,
    required this.chosen,
    required this.winner,
    required this.alternatives,
    required this.performedTempoBpm,
    required this.outcome,
    required this.frontierBefore,
    required this.pacedBefore,
    required this.transferableBefore,
    required this.handsTogetherReady,
    required this.handsTogetherOffered,
  });

  /// Where the chosen realization sat against the frontier.
  RealizationRank get realization => winner.rankKey!.realization;

  /// The demonstrated tempo at the span that was played, or zero.
  double get frontierAtSpan => frontierBefore[chosen.conditions.octaves] ?? 0;
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

  /// The census, when a slot anchors it.
  final String? census;

  const Anomaly({
    required this.detector,
    required this.severity,
    required this.summary,
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

  const Trajectory({
    required this.playerId,
    required this.seed,
    required this.slots,
  });
}
