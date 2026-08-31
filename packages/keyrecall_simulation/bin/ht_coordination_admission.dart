import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What coordination-aware challenge prediction refuses and bypasses admit.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('archetypes', defaultsTo: 'developing,uneven_hands,advanced')
    ..addOption('seeds', defaultsTo: '10')
    ..addOption('slots', defaultsTo: '60')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final archetypes = options.option('archetypes')!.split(',');
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final jobs = <TrajectoryJob>[
    for (final archetype in archetypes)
      for (var seed = 0; seed < seeds; seed++)
        TrajectoryJob(archetypeId: archetype, seed: seed),
  ];
  final buckets = List.generate(
    Platform.numberOfProcessors,
    (_) => <TrajectoryJob>[],
  );
  for (final (index, job) in jobs.indexed) {
    buckets[index % buckets.length].add(job);
  }
  final batches = await Future.wait([
    for (final bucket in buckets)
      if (bucket.isNotEmpty) Isolate.run(() => _countsFor(bucket, slots)),
  ]);
  final byArchetype = <String, _Counts>{};
  for (final batch in batches) {
    batch.forEach((archetype, counts) {
      byArchetype.update(
        archetype,
        (total) => total..absorb(counts),
        ifAbsent: () => counts,
      );
    });
  }

  stdout
    ..writeln(
      'coordination-aware HT challenge admission, $seeds independent runs x '
      '$slots slots\n'
      '  prior band = availability x execution would have been in band\n'
      '  product    = availability x execution x coordination\n'
      '  bottleneck = availability x min(execution, coordination)\n'
      '  logit      = availability x sigmoid(logit execution + logit coord)\n'
      '  caused     = availability x execution clears the floor, but the '
      'bottleneck does not\n'
      '  coord in   = prior band was out, coordination-aware band is in\n'
      '  weaker     = coordination is the weaker below-band motor factor\n'
      '  pass       = a named exception admitted that candidate\n',
    )
    ..writeln(
      '${'archetype'.padRight(15)}${'HT'.padLeft(9)}${'prior'.padLeft(10)}'
      '${'product'.padLeft(10)}${'bottleneck'.padLeft(12)}'
      '${'logit'.padLeft(10)}${'coord in'.padLeft(10)}',
    );

  for (final archetype in archetypes) {
    final counts = byArchetype[archetype] ?? _Counts();
    stdout.writeln(
      '${archetype.padRight(15)}${counts.handsTogether.toString().padLeft(9)}'
      '${counts.priorBand.toString().padLeft(10)}'
      '${counts.productBand.toString().padLeft(10)}'
      '${counts.newBand.toString().padLeft(12)}'
      '${counts.logitBand.toString().padLeft(10)}'
      '${counts.coordinationIn.toString().padLeft(10)}',
    );
  }

  stdout
    ..writeln()
    ..writeln(
      '${'archetype'.padRight(15)}${'caused'.padLeft(10)}'
      '${'pass'.padLeft(10)}${'won'.padLeft(8)}'
      '${'weaker'.padLeft(10)}${'pass'.padLeft(10)}${'won'.padLeft(8)}',
    );
  for (final archetype in archetypes) {
    final counts = byArchetype[archetype] ?? _Counts();
    stdout.writeln(
      '${archetype.padRight(15)}'
      '${counts.coordinationOut.toString().padLeft(10)}'
      '${counts.coordinationOutOverridden.toString().padLeft(10)}'
      '${counts.coordinationOutWon.toString().padLeft(8)}'
      '${counts.coordinationBound.toString().padLeft(10)}'
      '${counts.boundOverridden.toString().padLeft(10)}'
      '${counts.boundWon.toString().padLeft(8)}',
    );
    _writeReasons(
      'caused',
      counts.coordinationOutOverrides,
      counts.coordinationOutWinners,
    );
    _writeReasons('weaker', counts.boundOverrides, counts.boundWinners);
  }
}

void _writeReasons(
  String label,
  Map<String, int> admitted,
  Map<String, int> winners,
) {
  final reasons = admitted.keys.toList()
    ..sort((a, b) => admitted[b]!.compareTo(admitted[a]!));
  for (final reason in reasons) {
    stdout.writeln(
      '  ${'$label $reason'.padRight(31)}'
      '${admitted[reason].toString().padLeft(8)} candidates, '
      '${(winners[reason] ?? 0).toString().padLeft(4)} winners',
    );
  }
}

class _Counts {
  int handsTogether = 0;
  int priorBand = 0;
  int productBand = 0;
  int newBand = 0;
  int logitBand = 0;
  int coordinationOut = 0;
  int coordinationIn = 0;
  int coordinationOutOverridden = 0;
  int coordinationOutWon = 0;
  int coordinationBound = 0;
  int boundOverridden = 0;
  int boundWon = 0;
  final Map<String, int> coordinationOutOverrides = {};
  final Map<String, int> coordinationOutWinners = {};
  final Map<String, int> boundOverrides = {};
  final Map<String, int> boundWinners = {};

  void absorb(_Counts other) {
    handsTogether += other.handsTogether;
    priorBand += other.priorBand;
    productBand += other.productBand;
    newBand += other.newBand;
    logitBand += other.logitBand;
    coordinationOut += other.coordinationOut;
    coordinationIn += other.coordinationIn;
    coordinationOutOverridden += other.coordinationOutOverridden;
    coordinationOutWon += other.coordinationOutWon;
    coordinationBound += other.coordinationBound;
    boundOverridden += other.boundOverridden;
    boundWon += other.boundWon;
    for (final source in [
      (other.coordinationOutOverrides, coordinationOutOverrides),
      (other.coordinationOutWinners, coordinationOutWinners),
      (other.boundOverrides, boundOverrides),
      (other.boundWinners, boundWinners),
    ]) {
      source.$1.forEach((key, value) {
        source.$2[key] = (source.$2[key] ?? 0) + value;
      });
    }
  }
}

Map<String, _Counts> _countsFor(List<TrajectoryJob> jobs, int slots) {
  final byArchetype = <String, _Counts>{};

  for (final job in jobs) {
    final counts = byArchetype.putIfAbsent(job.archetypeId, _Counts.new);
    final coordinationOut = <int, Set<Exercise>>{};
    final coordinationBound = <int, Set<Exercise>>{};
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
      observeTraces: (slot, traces) {
        for (final trace in traces) {
          if (trace.exercise.conditions.hands != HandConfiguration.together ||
              trace.challengeStatus != StageStatus.reached) {
            continue;
          }
          counts.handsTogether++;
          final prior = _priorBand(trace.prediction);
          final current = trace.isWithinChallengeBand;
          if (prior) counts.priorBand++;
          if (_productBand(trace.prediction)) counts.productBand++;
          if (current) counts.newBand++;
          if (_logitBand(trace.prediction)) counts.logitBand++;
          if (!prior && current) counts.coordinationIn++;
          if (_coordinationCausedLowerRefusal(trace.prediction)) {
            counts.coordinationOut++;
            coordinationOut.putIfAbsent(slot, () => {}).add(trace.exercise);
            if (trace.challengeSurvived) {
              counts.coordinationOutOverridden++;
              final reason = trace.challengeBypass?.id ?? 'ordinary band';
              counts.coordinationOutOverrides[reason] =
                  (counts.coordinationOutOverrides[reason] ?? 0) + 1;
            }
          }

          final bound =
              trace.prediction.coordinationP < trace.prediction.executionP &&
              trace.prediction.overallP < v1SchedulerConfig.challenge.pMin;
          if (!bound) continue;
          counts.coordinationBound++;
          coordinationBound.putIfAbsent(slot, () => {}).add(trace.exercise);
          if (!trace.challengeSurvived) continue;
          counts.boundOverridden++;
          final reason = trace.challengeBypass?.id ?? 'ordinary band';
          counts.boundOverrides[reason] =
              (counts.boundOverrides[reason] ?? 0) + 1;
        }
      },
    );

    for (final slot in trajectory.slots) {
      if (coordinationOut[slot.index]?.contains(slot.chosen) == true) {
        counts.coordinationOutWon++;
        final reason = slot.winner.challengeBypass?.id ?? 'ordinary band';
        counts.coordinationOutWinners[reason] =
            (counts.coordinationOutWinners[reason] ?? 0) + 1;
      }
      if (coordinationBound[slot.index]?.contains(slot.chosen) != true) {
        continue;
      }
      counts.boundWon++;
      final reason = slot.winner.challengeBypass?.id ?? 'ordinary band';
      counts.boundWinners[reason] = (counts.boundWinners[reason] ?? 0) + 1;
    }
  }
  return byArchetype;
}

bool _priorBand(Prediction prediction) {
  final probability = prediction.materialAvailableP * prediction.executionP;
  return _inBand(probability);
}

bool _coordinationCausedLowerRefusal(Prediction prediction) =>
    prediction.materialAvailableP * prediction.executionP >=
        v1SchedulerConfig.challenge.pMin &&
    prediction.overallP < v1SchedulerConfig.challenge.pMin;

bool _productBand(Prediction prediction) {
  final probability =
      prediction.materialAvailableP *
      prediction.executionP *
      prediction.coordinationP;
  return _inBand(probability);
}

bool _logitBand(Prediction prediction) {
  final executionLogit = math.log(
    prediction.executionP / (1.0 - prediction.executionP),
  );
  final coordinationLogit = math.log(
    prediction.coordinationP / (1.0 - prediction.coordinationP),
  );
  final combined = 1.0 / (1.0 + math.exp(-executionLogit - coordinationLogit));
  return _inBand(prediction.materialAvailableP * combined);
}

bool _inBand(double probability) {
  return v1SchedulerConfig.challenge.pMin <= probability &&
      probability <= v1SchedulerConfig.challenge.pMax;
}
