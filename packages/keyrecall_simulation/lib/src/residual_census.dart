import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'arpeggio_policy_experiment.dart';
import 'scheduler_benchmark.dart';
import 'synthetic_player.dart';

/// One attempt, as the difference between what the model expected and what
/// happened.
///
/// Kept per attempt rather than per material so repeatability can be asked of
/// it: a mean residual says the model is off, and only a sequence says whether
/// it is off the same way every time.
class ResidualObservation {
  final String playerId;
  final int seed;
  final int index;
  final Exercise exercise;

  /// `motorScore - executionP`, the residual the execution channel learns from.
  final double execution;

  /// `topologyAccuracy - topologyP`.
  final double topology;

  const ResidualObservation({
    required this.playerId,
    required this.seed,
    required this.index,
    required this.exercise,
    required this.execution,
    required this.topology,
  });

  String get materialId => exercise.material.materialId;
  HandConfiguration get hands => exercise.conditions.hands;

  /// The cell a material-hand residual would live in.
  String get materialHand => '$materialId:${hands.id}';
}

/// Drives one archetype and reports what the model got wrong.
Future<List<ResidualObservation>> runResidualTrajectory({
  required ArpeggioPolicyScope scope,
  required SyntheticPlayer player,
  required int slots,
  int seed = 0,
}) async {
  final benchmark = await openBenchmarkSession(
    scope: scope,
    player: player,
    warmupSlots: slots,
    seed: seed,
  );
  return [
    for (final (index, record) in benchmark.session.journal.records.indexed)
      ?_observationOf(record, player.id, seed, index),
  ];
}

ResidualObservation? _observationOf(
  AttemptRecord record,
  String playerId,
  int seed,
  int index,
) {
  final prediction = record.decision?.prediction;
  if (prediction == null) return null;
  return switch (record.closure.measurement) {
    Measured(:final outcome) => ResidualObservation(
      playerId: playerId,
      seed: seed,
      index: index,
      exercise: record.exercise,
      execution: outcome.motorScore - prediction.executionP,
      topology: outcome.topologyAccuracy - prediction.topologyP,
    ),
    MeasurementUnavailable() => null,
  };
}

/// Residuals grouped by one partition of the attempts.
class ResidualPartition {
  final String axis;
  final Map<String, List<double>> byLevel;

  ResidualPartition(this.axis, this.byLevel);

  /// The partition of [observations] under [levelOf].
  factory ResidualPartition.of(
    String axis,
    Iterable<ResidualObservation> observations,
    String Function(ResidualObservation) levelOf,
    double Function(ResidualObservation) valueOf,
  ) {
    final byLevel = <String, List<double>>{};
    for (final observation in observations) {
      byLevel
          .putIfAbsent(levelOf(observation), () => [])
          .add(valueOf(observation));
    }
    return ResidualPartition(axis, byLevel);
  }

  /// The spread of level means, which is what a partition claims to explain.
  double get spreadOfMeans {
    final means = [for (final values in byLevel.values) mean(values)];
    return means.length < 2 ? 0 : standardDeviation(means);
  }
}

/// How much of a cell's residual comes back on its other attempts.
///
/// Split-half over each cell's own sequence: odd attempts against even ones.
/// Noise correlates at zero however large the cell means look, so this is the
/// measure that separates a repeatable effect from a spread of averages.
class SplitHalfReliability {
  final int cells;
  final int minimumAttempts;
  final double correlation;

  const SplitHalfReliability({
    required this.cells,
    required this.minimumAttempts,
    required this.correlation,
  });

  factory SplitHalfReliability.of(
    Iterable<ResidualObservation> observations,
    String Function(ResidualObservation) cellOf, {
    int minimumAttempts = 4,
    double Function(ResidualObservation)? valueOf,
  }) {
    final read = valueOf ?? (observation) => observation.execution;
    final cells = <String, List<double>>{};
    for (final observation in observations) {
      cells.putIfAbsent(cellOf(observation), () => []).add(read(observation));
    }
    final odd = <double>[];
    final even = <double>[];
    for (final values in cells.values) {
      if (values.length < minimumAttempts) continue;
      final first = <double>[];
      final second = <double>[];
      for (final (index, value) in values.indexed) {
        (index.isEven ? first : second).add(value);
      }
      if (first.isEmpty || second.isEmpty) continue;
      odd.add(mean(first));
      even.add(mean(second));
    }
    return SplitHalfReliability(
      cells: odd.length,
      minimumAttempts: minimumAttempts,
      correlation: correlationOf(odd, even),
    );
  }
}

/// [observations] with the mean of each [controlOf] group removed.
///
/// What a partition claims has to survive the partitions beside it. Hand and
/// tempo move the execution residual on their own, so a cell keyed by material
/// inherits their means unless they are taken out first, and a split-half over
/// uncentered cells measures how repeatable the control is rather than how
/// repeatable the cell is.
List<ResidualObservation> centeredBy(
  Iterable<ResidualObservation> observations,
  String Function(ResidualObservation) controlOf,
) {
  final groups = <String, List<double>>{};
  for (final observation in observations) {
    groups
        .putIfAbsent(controlOf(observation), () => [])
        .add(observation.execution);
  }
  final centers = {
    for (final group in groups.entries) group.key: mean(group.value),
  };
  return [
    for (final observation in observations)
      ResidualObservation(
        playerId: observation.playerId,
        seed: observation.seed,
        index: observation.index,
        exercise: observation.exercise,
        execution: observation.execution - centers[controlOf(observation)]!,
        topology: observation.topology,
      ),
  ];
}

double mean(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

double standardDeviation(List<double> values) {
  if (values.length < 2) return 0;
  final center = mean(values);
  final total = values.fold(
    0.0,
    (sum, value) => sum + (value - center) * (value - center),
  );
  return math.sqrt(total / (values.length - 1));
}

/// Variation below this is arithmetic noise rather than signal.
///
/// Residuals live in `[-1, 1]`, so a sum of squares this small across two or
/// more points means the values are constant to within a millionth. It matters
/// because a control that fully explains a cell leaves exactly that: values
/// that differ only in the last bits, whose correlation with each other is a
/// perfect one and means nothing.
const _negligibleSpread = 1e-12;

/// Pearson correlation, or zero where either side does not vary.
double correlationOf(List<double> left, List<double> right) {
  if (left.length < 2 || left.length != right.length) return 0;
  final leftCenter = mean(left);
  final rightCenter = mean(right);
  var covariance = 0.0;
  var leftSpread = 0.0;
  var rightSpread = 0.0;
  for (var index = 0; index < left.length; index++) {
    final a = left[index] - leftCenter;
    final b = right[index] - rightCenter;
    covariance += a * b;
    leftSpread += a * a;
    rightSpread += b * b;
  }
  if (leftSpread <= _negligibleSpread || rightSpread <= _negligibleSpread) {
    return 0;
  }
  return covariance / math.sqrt(leftSpread * rightSpread);
}
