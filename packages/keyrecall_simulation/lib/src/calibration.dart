import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'python_compatible_random.dart';
import 'synthetic_player.dart';

/// One attempt as it looks from outside the learner.
///
/// What was asked and what happened, which is all a device journal records and
/// all a fit is entitled to read. Nothing here is a scheduler quantity.
class AttemptObservation {
  final Exercise exercise;
  final Outcome outcome;

  const AttemptObservation(this.exercise, this.outcome);
}

/// What a sitting looked like, as distributions rather than a sequence.
///
/// A fit compares these rather than reproducing attempts one by one. One human
/// sitting is not deterministic, and a candidate that matched it attempt by
/// attempt would be fitting its noise.
class SittingProfile {
  final int attempts;

  /// Median tempo actually played, by hand configuration.
  final Map<HandConfiguration, double> achievedTempo;

  /// Median motor score, by hand configuration.
  final Map<HandConfiguration, double> motor;

  /// Median played tempo over requested tempo.
  final double tempoRatio;

  /// How much the played tempo follows the requested one, as the slope of log
  /// played against log requested.
  ///
  /// The model blends the two in log tempo, so this reads compliance almost
  /// directly: one is somebody who plays what the count-in says, zero somebody
  /// who plays their own pace whatever it says. Without it the played tempo
  /// alone cannot separate a fast player who complies from a slow one who does
  /// not, and a fit will report a natural tempo it cannot see.
  final double tempoSlope;

  /// Share of attempts played well above what was asked for.
  final double sprintShare;

  /// Share of attempts that were completed.
  final double completionRate;

  /// Median motor score on material the sitting had not seen before, against
  /// material it had.
  final double? unfamiliarMotor;
  final double? familiarMotor;

  const SittingProfile({
    required this.attempts,
    required this.achievedTempo,
    required this.motor,
    required this.tempoRatio,
    required this.tempoSlope,
    required this.sprintShare,
    required this.completionRate,
    required this.unfamiliarMotor,
    required this.familiarMotor,
  });

  /// The hands-together cost, in motor score against the better single hand.
  ///
  /// Null when the sitting holds no hands-together work, which a first sitting
  /// often does not.
  double? get handsTogetherPenalty {
    final together = motor[HandConfiguration.together];
    final single = [
      ?motor[HandConfiguration.right],
      ?motor[HandConfiguration.left],
    ];
    if (together == null || single.isEmpty) return null;
    return single.reduce(math.max) - together;
  }
}

/// The profile [attempts] make, in the order they happened.
SittingProfile profileOf(List<AttemptObservation> attempts) {
  final byHands = <HandConfiguration, List<AttemptObservation>>{};
  final seen = <String>{};
  final unfamiliar = <double>[];
  final familiar = <double>[];
  var sprints = 0;
  var completed = 0;
  final ratios = <double>[];

  for (final attempt in attempts) {
    (byHands[attempt.exercise.conditions.hands] ??= []).add(attempt);
    final materialId = attempt.exercise.material.materialId;
    (seen.add(materialId) ? unfamiliar : familiar).add(
      attempt.outcome.motorScore,
    );
    ratios.add(attempt.outcome.achievedTempoRatio);
    if (attempt.outcome.achievedTempoRatio >= 1.2) sprints++;
    if (attempt.outcome.completed) completed++;
  }

  return SittingProfile(
    attempts: attempts.length,
    tempoSlope: _slope([
      for (final attempt in attempts)
        if (attempt.outcome.achievedTempoRatio > 0)
          (
            math.log(attempt.exercise.conditions.tempoBpm),
            math.log(
              attempt.exercise.conditions.tempoBpm *
                  attempt.outcome.achievedTempoRatio,
            ),
          ),
    ]),
    achievedTempo: {
      for (final entry in byHands.entries)
        entry.key: _median([
          for (final attempt in entry.value)
            attempt.exercise.conditions.tempoBpm *
                attempt.outcome.achievedTempoRatio,
        ]),
    },
    motor: {
      for (final entry in byHands.entries)
        entry.key: _median([
          for (final attempt in entry.value) attempt.outcome.motorScore,
        ]),
    },
    tempoRatio: _median(ratios),
    sprintShare: attempts.isEmpty ? 0 : sprints / attempts.length,
    completionRate: attempts.isEmpty ? 0 : completed / attempts.length,
    unfamiliarMotor: unfamiliar.isEmpty ? null : _median(unfamiliar),
    familiarMotor: familiar.isEmpty ? null : _median(familiar),
  );
}

/// Plays [presented] through [player], without a scheduler.
///
/// The exercises are the ones a sitting actually asked for, so a candidate is
/// answering the same questions the person answered. Replaying a fit through
/// the scheduler instead would fit the policy and the player at once.
List<AttemptObservation> replay(
  SyntheticPlayer player,
  List<Exercise> presented, {
  int seed = 0,
}) {
  final rng = PythonCompatibleRandom(seed);
  final playing = player.begin();
  return [
    for (final exercise in presented)
      AttemptObservation(exercise, playing.play(exercise, rng)),
  ];
}

/// How far apart two sittings look.
///
/// Scaled so that each term is roughly a proportion: tempos as relative error,
/// scores and rates as absolute difference. Terms only one profile can answer
/// are skipped rather than defaulted, which keeps a sitting with no
/// hands-together work from being fitted on a quantity it never observed.
double profileDistance(SittingProfile a, SittingProfile b) {
  var total = 0.0;
  var terms = 0;

  void compare(double? left, double? right, {bool relative = false}) {
    if (left == null || right == null) return;
    terms++;
    total += relative
        ? (left - right).abs() / math.max(left, right).clamp(1e-9, 1e9)
        : (left - right).abs();
  }

  for (final hands in HandConfiguration.values) {
    compare(a.achievedTempo[hands], b.achievedTempo[hands], relative: true);
    compare(a.motor[hands], b.motor[hands]);
  }
  compare(a.tempoRatio, b.tempoRatio, relative: true);
  compare(a.tempoSlope, b.tempoSlope);
  compare(a.sprintShare, b.sprintShare);
  compare(a.completionRate, b.completionRate);
  compare(a.unfamiliarMotor, b.unfamiliarMotor);
  compare(a.familiarMotor, b.familiarMotor);

  return terms == 0 ? double.infinity : total / terms;
}

/// A knob a fit is allowed to move.
///
/// Staged deliberately. Where a learner starts and how fast they improve are
/// separate hypotheses, and a fit that moved both at once could explain a weak
/// sitting either way; a single sitting cannot see improvement at all, so
/// [learningRate] belongs to a fit across several.
enum PlayerParameter {
  naturalTempoRight,
  naturalTempoLeft,
  rightHandAbility,
  leftHandAbility,
  handsTogetherAbility,
  familiarity,
  tempoCompliance,
  sprintProbability,
  learningRate,
}

/// The parameters a first sitting can speak to.
const Set<PlayerParameter> initialConditions = {
  PlayerParameter.naturalTempoRight,
  PlayerParameter.naturalTempoLeft,
  PlayerParameter.rightHandAbility,
  PlayerParameter.leftHandAbility,
  PlayerParameter.handsTogetherAbility,
  PlayerParameter.familiarity,
};

/// How faithfully the person follows what was asked.
const Set<PlayerParameter> behavioralNoise = {
  PlayerParameter.tempoCompliance,
  PlayerParameter.sprintProbability,
};

/// What one sitting can be fitted on at once.
///
/// Compliance belongs here rather than to a later stage, because the played
/// tempo is a blend of the requested one and the natural one and neither is
/// identified without the other: holding compliance at a guess reports a
/// natural tempo that is really a statement about the guess. They are one
/// block, and [SittingProfile.tempoSlope] is what separates them.
const Set<PlayerParameter> firstSitting = {
  ...initialConditions,
  ...behavioralNoise,
};

/// One candidate and how far its sitting was from the observed one.
class PlayerFit {
  final SyntheticPlayer player;
  final double distance;

  const PlayerFit(this.player, this.distance);
}

/// Candidate players whose sitting resembles [target], closest first.
///
/// Simulation-based matching rather than an optimizer: sample players, play the
/// same exercises through each, and keep the ones whose sitting looks like the
/// observed one. The answer is the ensemble, because several parameter sets
/// reproduce one sitting and reporting a single point estimate would claim a
/// precision the data does not carry.
List<PlayerFit> fitPlayers({
  required SittingProfile target,
  required List<Exercise> presented,
  required Set<PlayerParameter> vary,
  SyntheticPlayer? from,
  int samples = 400,
  int keep = 20,
  int seed = 0,
  int replays = 3,
}) {
  final rng = PythonCompatibleRandom(seed);
  final start = from ?? PlayerArchetypeSeed.middling;
  final fits = <PlayerFit>[];

  for (var sample = 0; sample < samples; sample++) {
    final candidate = _sample(start, vary, rng, sample);
    // Averaged over a few draws, so a candidate is not chosen for one lucky
    // replay of a stochastic player.
    var total = 0.0;
    for (var replayIndex = 0; replayIndex < replays; replayIndex++) {
      total += profileDistance(
        target,
        profileOf(replay(candidate, presented, seed: replayIndex)),
      );
    }
    fits.add(PlayerFit(candidate, total / replays));
  }

  fits.sort((a, b) => a.distance.compareTo(b.distance));
  return fits.take(keep).toList();
}

/// The range an ensemble puts a parameter in.
///
/// Reported instead of a best value: a wide range says the sitting did not
/// identify the parameter, which is as useful an answer as a narrow one.
({double low, double median, double high}) rangeOf(
  List<PlayerFit> ensemble,
  double Function(SyntheticPlayer player) read,
) {
  final values = [for (final fit in ensemble) read(fit.player)]..sort();
  if (values.isEmpty) return (low: 0, median: 0, high: 0);
  return (
    low: values[(values.length * 0.1).floor()],
    median: values[values.length ~/ 2],
    high: values[math.min(values.length - 1, (values.length * 0.9).floor())],
  );
}

/// The player a search starts from when nothing is known.
///
/// Deliberately unremarkable, since every parameter a fit varies is drawn over
/// its own range and the rest are held here.
abstract final class PlayerArchetypeSeed {
  static SyntheticPlayer get middling => SyntheticPlayer(
    id: 'fitted',
    placement: PlacementTier.someExperience,
    naturalTempoRightBpm: 100,
    naturalTempoLeftBpm: 95,
    tempoCompliance: 0.8,
    rightHandAbility: 0.5,
    leftHandAbility: 0.3,
    handsTogetherAbility: -0.5,
    familiarity: 0.6,
  );
}

SyntheticPlayer _sample(
  SyntheticPlayer start,
  Set<PlayerParameter> vary,
  PythonCompatibleRandom rng,
  int index,
) {
  double? pick(PlayerParameter parameter, double low, double high) =>
      vary.contains(parameter) ? low + rng.nextDouble() * (high - low) : null;

  return start.copyWith(
    id: 'fitted_$index',
    naturalTempoRightBpm: pick(PlayerParameter.naturalTempoRight, 40, 200),
    naturalTempoLeftBpm: pick(PlayerParameter.naturalTempoLeft, 40, 200),
    rightHandAbility: pick(PlayerParameter.rightHandAbility, -2.5, 2.5),
    leftHandAbility: pick(PlayerParameter.leftHandAbility, -2.5, 2.5),
    handsTogetherAbility: pick(PlayerParameter.handsTogetherAbility, -3, 2),
    familiarity: pick(PlayerParameter.familiarity, 0.05, 0.99),
    tempoCompliance: pick(PlayerParameter.tempoCompliance, 0, 1),
    sprintProbability: pick(PlayerParameter.sprintProbability, 0, 0.5),
    learningRate: pick(PlayerParameter.learningRate, 0, 0.05),
  );
}

/// The least-squares slope of the second value on the first.
///
/// Zero when the requested tempo never varied, which is not a compliant player
/// but a sitting that could not tell.
double _slope(List<(double, double)> points) {
  if (points.length < 2) return 0;
  final meanX =
      points.map((point) => point.$1).reduce((a, b) => a + b) / points.length;
  final meanY =
      points.map((point) => point.$2).reduce((a, b) => a + b) / points.length;
  var covariance = 0.0;
  var variance = 0.0;
  for (final (x, y) in points) {
    covariance += (x - meanX) * (y - meanY);
    variance += (x - meanX) * (x - meanX);
  }
  return variance <= 1e-12 ? 0 : covariance / variance;
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
