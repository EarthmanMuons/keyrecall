import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'python_compatible_random.dart';
import 'synthetic_player.dart';
import 'trajectory.dart';

/// Which part of the supply-then-withdraw protocol an attempt belongs to.
enum PulsePhase {
  /// Count-in only, before any pulse was supplied.
  before,

  /// A pulse continuing through the attempt.
  supplied,

  /// Count-in only again, once the pulse has been withdrawn.
  withdrawn,
}

/// How one player played in one phase, averaged over every attempt in it.
class PulsePhaseReading {
  final PulsePhase phase;
  final int attempts;
  final double temporalStability;
  final double continuity;

  /// Achieved over requested tempo.
  final double tempoRatio;

  /// The share of attempts whose outcome tested keeping the pulse alone.
  final double pulseTested;

  const PulsePhaseReading({
    required this.phase,
    required this.attempts,
    required this.temporalStability,
    required this.continuity,
    required this.tempoRatio,
    required this.pulseTested,
  });
}

/// What supplying a pulse and withdrawing it did for one player.
class PulseResponse {
  final String playerId;
  final Map<PulsePhase, PulsePhaseReading> phases;

  const PulseResponse({required this.playerId, required this.phases});

  PulsePhaseReading operator [](PulsePhase phase) => phases[phase]!;
}

/// Plays [exercise] for [player] through the three phases in order, fresh for
/// each seed, with [attemptsPerPhase] attempts in each.
///
/// The exercise never changes, so a phase differs from its neighbors in the
/// pulse alone and in whatever the player learned along the way. A player
/// with no pulse traits reads that learning on its own.
PulseResponse pulseResponseOf(
  SyntheticPlayer player, {
  required Exercise exercise,
  int seeds = 20,
  int attemptsPerPhase = 6,
}) {
  final countIn = PresentationDelivery(tempo: TempoDelivery.complete(4));
  final metronome = PresentationDelivery(
    tempo: TempoDelivery.complete(
      4,
      continuingBeats: realize(exercise).moments.length + 4,
    ),
  );
  final outcomes = {for (final phase in PulsePhase.values) phase: <Outcome>[]};
  for (var seed = 0; seed < seeds; seed++) {
    final rng = PythonCompatibleRandom(seed);
    final playing = player.begin();
    for (final phase in PulsePhase.values) {
      for (var attempt = 0; attempt < attemptsPerPhase; attempt++) {
        outcomes[phase]!.add(
          playing.play(
            exercise,
            rng,
            delivery: phase == PulsePhase.supplied ? metronome : countIn,
          ),
        );
      }
    }
  }
  return PulseResponse(
    playerId: player.id,
    phases: {
      for (final MapEntry(key: phase, value: played) in outcomes.entries)
        phase: PulsePhaseReading(
          phase: phase,
          attempts: played.length,
          temporalStability: _meanOf([
            for (final outcome in played) ?outcome.temporalStability,
          ]),
          continuity: _meanOf([
            for (final outcome in played) ?outcome.continuity,
          ]),
          tempoRatio: _meanOf([
            for (final outcome in played) ?outcome.measuredTempoRatio,
          ]),
          pulseTested:
              played
                  .where((outcome) => outcome.pulseMaintenance.isTested)
                  .length /
              played.length,
        ),
    },
  );
}

/// How often the same kind of timing evidence comes back within a session.
///
/// What a detector that waits for several observations of one kind before
/// acting would have to work with. [keyOf] decides what counts as the same
/// kind, which is the question this exists to answer: an execution context,
/// or something coarser such as a hand configuration.
///
/// Only attempts that started and tested the pulse count. Nothing here judges
/// whether the timing was good, because no threshold for that exists yet.
class TimingRecurrence {
  /// Sessions read.
  final int sessions;

  /// Timing observations across them.
  final int observations;

  /// Distinct keys observed, summed over sessions.
  final int keys;

  /// Keys, summed over sessions, observed at least `n` times in their
  /// session, by `n`.
  final Map<int, int> keysObservedAtLeast;

  /// Sessions in which some key was observed at least `n` times, by `n`.
  final Map<int, int> sessionsWithAKeyAtLeast;

  /// Slots between consecutive observations of one key in one session.
  final List<int> gaps;

  const TimingRecurrence({
    required this.sessions,
    required this.observations,
    required this.keys,
    required this.keysObservedAtLeast,
    required this.sessionsWithAKeyAtLeast,
    required this.gaps,
  });

  /// Counted from the sessions of [trajectories], for `n` in [depths].
  static TimingRecurrence of<K>(
    Iterable<Trajectory> trajectories, {
    required K Function(Exercise exercise) keyOf,
    List<int> depths = const [2, 3],
  }) {
    var sessions = 0;
    var observations = 0;
    var keys = 0;
    final keysAtLeast = {for (final depth in depths) depth: 0};
    final sessionsAtLeast = {for (final depth in depths) depth: 0};
    final gaps = <int>[];
    for (final trajectory in trajectories) {
      for (var session = 0; session < trajectory.sessions.length; session++) {
        sessions++;
        final positions = <K, List<int>>{};
        for (final (position, slot) in trajectory.slotsOf(session).indexed) {
          if (!_timedUnaided(slot.outcome)) continue;
          observations++;
          positions.putIfAbsent(keyOf(slot.chosen), () => []).add(position);
        }
        keys += positions.length;
        for (final seen in positions.values) {
          for (var i = 1; i < seen.length; i++) {
            gaps.add(seen[i] - seen[i - 1]);
          }
        }
        for (final depth in depths) {
          final reaching = positions.values
              .where((seen) => seen.length >= depth)
              .length;
          keysAtLeast[depth] = keysAtLeast[depth]! + reaching;
          if (reaching > 0) {
            sessionsAtLeast[depth] = sessionsAtLeast[depth]! + 1;
          }
        }
      }
    }
    return TimingRecurrence(
      sessions: sessions,
      observations: observations,
      keys: keys,
      keysObservedAtLeast: keysAtLeast,
      sessionsWithAKeyAtLeast: sessionsAtLeast,
      gaps: gaps,
    );
  }

  /// The median of [gaps], or null when nothing recurred.
  double? get medianGap {
    if (gaps.isEmpty) return null;
    final ordered = [...gaps]..sort();
    final middle = ordered.length ~/ 2;
    return ordered.length.isOdd
        ? ordered[middle].toDouble()
        : (ordered[middle - 1] + ordered[middle]) / 2;
  }
}

/// What timing remediation did across sessions the scheduler ran.
///
/// Read from the trajectories themselves: a cycle is a slot chosen under
/// [ChallengeBypass.pulseSupport], and what it showed is the steadiness of
/// that slot and of the withdrawal after it.
class RemediationReading {
  final int sessions;

  /// Sessions in which a cycle opened.
  final int sessionsWithACycle;

  /// Cycles opened, over every session.
  final int cycles;

  /// Cycles whose withdrawal was reached before the session ended.
  final int withdrawals;

  /// Supported attempts whose outcome still claimed a pulse the player held,
  /// which the evidence rule forbids.
  final int supportedButTested;

  /// Temporal stability of the supported attempts, and of the withdrawals,
  /// where they started.
  ///
  /// An attempt that never started records steadiness as zero, which is no
  /// playing rather than unsteady playing.
  final List<double> supportedSteadiness;
  final List<double> withdrawnSteadiness;

  const RemediationReading({
    required this.sessions,
    required this.sessionsWithACycle,
    required this.cycles,
    required this.withdrawals,
    required this.supportedButTested,
    required this.supportedSteadiness,
    required this.withdrawnSteadiness,
  });

  factory RemediationReading.of(Iterable<Trajectory> trajectories) {
    var sessions = 0;
    var sessionsWithACycle = 0;
    var cycles = 0;
    var withdrawals = 0;
    var supportedButTested = 0;
    final supported = <double>[];
    final withdrawn = <double>[];
    for (final trajectory in trajectories) {
      for (var session = 0; session < trajectory.sessions.length; session++) {
        sessions++;
        var opened = false;
        for (final slot in trajectory.slotsOf(session)) {
          switch (slot.winner.challengeBypass) {
            case ChallengeBypass.pulseSupport:
              opened = true;
              cycles++;
              if (slot.outcome.pulseMaintenance.isTested) supportedButTested++;
              if (_steadinessOf(slot.outcome) case final steadiness?) {
                supported.add(steadiness);
              }
            case ChallengeBypass.pulseWithdrawal:
              withdrawals++;
              if (_steadinessOf(slot.outcome) case final steadiness?) {
                withdrawn.add(steadiness);
              }
            default:
          }
        }
        if (opened) sessionsWithACycle++;
      }
    }
    return RemediationReading(
      sessions: sessions,
      sessionsWithACycle: sessionsWithACycle,
      cycles: cycles,
      withdrawals: withdrawals,
      supportedButTested: supportedButTested,
      supportedSteadiness: supported,
      withdrawnSteadiness: withdrawn,
    );
  }

  double get meanSupportedSteadiness => _meanOf(supportedSteadiness);
  double get meanWithdrawnSteadiness => _meanOf(withdrawnSteadiness);
}

double? _steadinessOf(Outcome outcome) =>
    outcome.started ? outcome.temporalStability : null;

bool _timedUnaided(Outcome outcome) =>
    outcome.started &&
    outcome.temporalStability != null &&
    outcome.pulseMaintenance.isTested;

double _meanOf(List<double> values) => values.isEmpty
    ? double.nan
    : values.reduce((a, b) => a + b) / values.length;
