import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:keyrecall_simulation/keyrecall_simulation.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'archetypes',
      defaultsTo: 'true_beginner,developing,uneven_hands,advanced',
    )
    ..addOption('seeds', defaultsTo: '10')
    ..addOption('slots', defaultsTo: '60')
    ..addOption('window', defaultsTo: '12')
    ..addOption('share-floor', defaultsTo: '0.5')
    ..addOption('min-attempts', defaultsTo: '4')
    ..addOption('set-aside-at', defaultsTo: '0.15')
    ..addFlag('require-ready-alternative', defaultsTo: false)
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final archetypes = options.option('archetypes')!.split(',');
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final pacing = RealizationFamilyPacingConfig(
    window: int.parse(options.option('window')!),
    shareFloor: double.parse(options.option('share-floor')!),
    minFamilyAttempts: int.parse(options.option('min-attempts')!),
    setAsideAt: double.parse(options.option('set-aside-at')!),
    requireReadyAlternative: options.flag('require-ready-alternative'),
  );
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
      if (bucket.isNotEmpty) Isolate.run(() => _runJobs(bucket, slots, pacing)),
  ]);
  final results = <String, _Relief>{};
  for (final batch in batches) {
    batch.forEach((archetype, relief) {
      results.update(
        archetype,
        (total) => total..absorb(relief),
        ifAbsent: () => relief,
      );
    });
  }

  stdout.writeln(
    'alternative readiness at set-aside points, '
    '$seeds independent runs x $slots slots, '
    'window ${pacing.window}, floor ${pacing.shareFloor}, '
    'min ${pacing.minFamilyAttempts}, set aside at ${pacing.setAsideAt}, '
    'ready alternative required ${pacing.requireReadyAlternative}',
  );
  for (final archetype in archetypes) {
    _writeArchetype(archetype, results[archetype] ?? _Relief());
  }
}

void _writeArchetype(String archetype, _Relief relief) {
  stdout
    ..writeln('\n$archetype')
    ..writeln(
      '  set-aside slots: ${relief.setAsides}; '
      'nothing to relieve: ${relief.unrelieved}; '
      'no ready alternative: ${relief.unready}',
    );
  if (relief.setAsides == 0) return;

  stdout
    ..writeln('  readiness (min / median / mean / max)')
    ..writeln('    pressured overallP        ${_summary(relief.pressuredP)}')
    ..writeln('    relieving overallP        ${_summary(relief.relievingP)}')
    ..writeln('    relieving - pressured     ${_summary(relief.readinessGap)}')
    ..writeln(
      '  relieving at least as ready: '
      '${_share(relief.relievingAtLeastAsReady, relief.setAsides)}',
    )
    ..writeln(
      '  within challenge band: pressured '
      '${_share(relief.pressuredInBand, relief.setAsides)}, relieving '
      '${_share(relief.relievingInBand, relief.setAsides)}',
    )
    ..writeln(
      '  fully eligible: pressured '
      '${_share(relief.pressuredFullyEligible, relief.setAsides)}, relieving '
      '${_share(relief.relievingFullyEligible, relief.setAsides)}',
    )
    ..writeln(
      '  relieving choice taken: '
      '${_share(relief.relievingChosen, relief.setAsides)}',
    )
    ..writeln(
      '  relieving choice managed: '
      '${_share(relief.relievingManaged, relief.relievingChosen)}, '
      'advanced a frontier: '
      '${_share(relief.relievingAdvanced, relief.relievingChosen)}',
    )
    ..writeln('  substituted family:');
  _writeMap(relief.familyPairs);
  stdout.writeln('  substituted category:');
  _writeMap(relief.categoryPairs);
}

String _summary(List<double> values) {
  if (values.isEmpty) return '-';
  final sorted = [...values]..sort();
  final mean = sorted.reduce((a, b) => a + b) / sorted.length;
  final median = sorted[(sorted.length - 1) ~/ 2];
  return '${_signed(sorted.first)} / ${_signed(median)} / '
      '${_signed(mean)} / ${_signed(sorted.last)}';
}

String _signed(double value) =>
    '${value >= 0 ? ' ' : ''}${value.toStringAsFixed(3)}';

String _share(int numerator, int denominator) => denominator == 0
    ? '-'
    : '$numerator/$denominator '
          '(${(100 * numerator / denominator).toStringAsFixed(1)}%)';

void _writeMap(Map<String, int> values) {
  if (values.isEmpty) {
    stdout.writeln('    none');
    return;
  }
  final entries = values.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in entries) {
    stdout.writeln(
      '    ${entry.key.padRight(62)}${entry.value.toString().padLeft(5)}',
    );
  }
}

Map<String, _Relief> _runJobs(
  List<TrajectoryJob> jobs,
  int slots,
  RealizationFamilyPacingConfig pacing,
) {
  final results = <String, _Relief>{};
  for (final job in jobs) {
    final pipeline = FamilyPacedPipeline(
      learner: const LearnerModel(),
      pacing: RealizationFamilyPacing(config: pacing),
    );
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
      pipeline: pipeline,
    );
    results
        .putIfAbsent(job.archetypeId, _Relief.new)
        .observe(pipeline, trajectory);
  }
  return results;
}

String _familyLabel(Exercise exercise) =>
    (handMotionFamilies(exercise).toList()..sort()).join('+');

String _category(CandidateTrace trace) =>
    trace.challengeBypass?.id ?? 'ordinary';

class _Relief {
  int setAsides = 0;
  int unrelieved = 0;
  int unready = 0;
  int relievingAtLeastAsReady = 0;
  int pressuredInBand = 0;
  int relievingInBand = 0;
  int pressuredFullyEligible = 0;
  int relievingFullyEligible = 0;
  int relievingChosen = 0;
  int relievingManaged = 0;
  int relievingAdvanced = 0;
  final List<double> pressuredP = [];
  final List<double> relievingP = [];
  final List<double> readinessGap = [];
  final Map<String, int> familyPairs = {};
  final Map<String, int> categoryPairs = {};

  void observe(FamilyPacedPipeline pipeline, Trajectory trajectory) {
    unrelieved += pipeline.unrelievedSlots;
    unready += pipeline.unreadySlots;
    for (final setAside in pipeline.setAsides) {
      setAsides++;
      final pressured = setAside.pressured;
      final relieving = setAside.relieving;
      pressuredP.add(pressured.prediction.overallP);
      relievingP.add(relieving.prediction.overallP);
      final gap = relieving.prediction.overallP - pressured.prediction.overallP;
      readinessGap.add(gap);
      if (gap >= 0) relievingAtLeastAsReady++;
      if (pressured.isWithinChallengeBand) pressuredInBand++;
      if (relieving.isWithinChallengeBand) relievingInBand++;
      if (pressured.eligibility.tier == EligibilityTier.fullyEligible) {
        pressuredFullyEligible++;
      }
      if (relieving.eligibility.tier == EligibilityTier.fullyEligible) {
        relievingFullyEligible++;
      }
      final pair =
          '${_familyLabel(pressured.exercise)} -> '
          '${_familyLabel(relieving.exercise)}';
      familyPairs[pair] = (familyPairs[pair] ?? 0) + 1;
      final categories = '${_category(pressured)} -> ${_category(relieving)}';
      categoryPairs[categories] = (categoryPairs[categories] ?? 0) + 1;

      if (setAside.slot >= trajectory.slots.length) continue;
      final slot = trajectory.slots[setAside.slot];
      if (slot.chosen != relieving.exercise) continue;
      relievingChosen++;
      if (slot.managedExecution) relievingManaged++;
      if (slot.frontierAdvanced) relievingAdvanced++;
    }
  }

  void absorb(_Relief other) {
    setAsides += other.setAsides;
    unrelieved += other.unrelieved;
    unready += other.unready;
    relievingAtLeastAsReady += other.relievingAtLeastAsReady;
    pressuredInBand += other.pressuredInBand;
    relievingInBand += other.relievingInBand;
    pressuredFullyEligible += other.pressuredFullyEligible;
    relievingFullyEligible += other.relievingFullyEligible;
    relievingChosen += other.relievingChosen;
    relievingManaged += other.relievingManaged;
    relievingAdvanced += other.relievingAdvanced;
    pressuredP.addAll(other.pressuredP);
    relievingP.addAll(other.relievingP);
    readinessGap.addAll(other.readinessGap);
    for (final source in [
      (other.familyPairs, familyPairs),
      (other.categoryPairs, categoryPairs),
    ]) {
      source.$1.forEach((key, value) {
        source.$2[key] = (source.$2[key] ?? 0) + value;
      });
    }
  }
}
