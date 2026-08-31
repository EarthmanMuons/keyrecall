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
  final points = relief.points;
  if (points.isEmpty) return;

  stdout
    ..writeln('  readiness (min / median / mean / max)')
    ..writeln(
      '    pressured overallP        '
      '${_summary([for (final p in points) p.pressuredP])}',
    )
    ..writeln(
      '    relieving overallP        '
      '${_summary([for (final p in points) p.relievingP])}',
    )
    ..writeln(
      '    relieving - pressured     '
      '${_summary([for (final p in points) p.readinessGap])}',
    )
    ..writeln(
      '  relieving at least as ready: '
      '${_share(points.where((p) => p.isReady).length, points.length)}',
    )
    ..writeln(
      '  within challenge band: pressured '
      '${_share(points.where((p) => p.pressuredInBand).length, points.length)}'
      ', relieving '
      '${_share(points.where((p) => p.relievingInBand).length, points.length)}',
    )
    ..writeln(
      '  fully eligible: pressured '
      '${_share(points.where((p) => p.pressuredFullyEligible).length, points.length)}'
      ', relieving '
      '${_share(points.where((p) => p.relievingFullyEligible).length, points.length)}',
    )
    ..writeln(
      '  relieving choice taken: '
      '${_share(points.where((p) => p.taken).length, points.length)}',
    )
    ..writeln(
      '  relieving already outranks pressured: '
      '${_share(points.where((p) => p.outranksPressured).length, points.length)}',
    );

  final taken = points.where((p) => p.taken && p.isEffective).toList();
  stdout
    ..writeln('  ranking terms (mean, pressured -> relieving)')
    ..writeln(
      '    retention                 '
      '${_mean([for (final p in points) p.pressuredRetention])} -> '
      '${_mean([for (final p in points) p.relievingRetention])}',
    )
    ..writeln(
      '    information               '
      '${_mean([for (final p in points) p.pressuredInformation])} -> '
      '${_mean([for (final p in points) p.relievingInformation])}',
    )
    ..writeln('  realization rank of the relieving choice')
    ..writeln(
      '    ${'rank'.padRight(12)}${'n'.padLeft(6)}${'ready'.padLeft(14)}'
      '${'taken'.padLeft(14)}${'managed'.padLeft(14)}'
      '${'advanced'.padLeft(14)}',
    );
  for (final rank in RealizationRank.values) {
    final group = points.where((p) => p.relievingRank == rank).toList();
    if (group.isEmpty) continue;
    final chosen = group.where((p) => p.taken).length;
    stdout.writeln(
      '    ${rank.id.toLowerCase().padRight(12)}'
      '${group.length.toString().padLeft(6)}'
      '${_share(group.where((p) => p.isReady).length, group.length).padLeft(14)}'
      '${_share(chosen, group.length).padLeft(14)}'
      '${_share(group.where((p) => p.managed).length, chosen).padLeft(14)}'
      '${_share(group.where((p) => p.advanced).length, chosen).padLeft(14)}',
    );
  }

  stdout
    ..writeln('  realization rank of the pressured candidate')
    ..writeln('    ${_rankCounts(points)}')
    ..writeln(
      '  candidate relief criteria, over ${taken.length} '
      'effective taken slots',
    )
    ..writeln(
      '    ${'criterion'.padRight(26)}${'kept'.padLeft(14)}'
      '${'managed'.padLeft(14)}${'advanced'.padLeft(14)}'
      '${'useful'.padLeft(14)}',
    );
  final criteria = <(String, bool Function(_Point))>[
    ('any relief', (p) => true),
    ('ready', (p) => p.isReady),
    ('opportunity', (p) => p.hasOpportunity),
    ('ready + opportunity', (p) => p.isReady && p.hasOpportunity),
    ('ready + holds rank', (p) => p.isReady && p.holdsRank),
    ('holds rank', (p) => p.holdsRank),
  ];
  for (final (label, matches) in criteria) {
    final kept = taken.where(matches).toList();
    stdout.writeln(
      '    ${label.padRight(26)}'
      '${_share(kept.length, taken.length).padLeft(14)}'
      '${_share(kept.where((p) => p.managed).length, kept.length).padLeft(14)}'
      '${_share(kept.where((p) => p.advanced).length, kept.length).padLeft(14)}'
      '${_share(kept.where((p) => p.wasUseful).length, kept.length).padLeft(14)}',
    );
  }

  stdout
    ..writeln('  taken relief, useful vs not')
    ..writeln(
      '    ${'group'.padRight(12)}${'n'.padLeft(6)}${'readinessGap'.padLeft(14)}'
      '${'retention'.padLeft(12)}${'information'.padLeft(13)}'
      '${'ranks'.padLeft(30)}',
    );
  for (final (label, group) in [
    ('useful', taken.where((p) => p.wasUseful).toList()),
    ('not useful', taken.where((p) => !p.wasUseful).toList()),
  ]) {
    if (group.isEmpty) continue;
    stdout.writeln(
      '    ${label.padRight(12)}${group.length.toString().padLeft(6)}'
      '${_mean([for (final p in group) p.readinessGap]).padLeft(14)}'
      '${_mean([for (final p in group) p.relievingRetention]).padLeft(12)}'
      '${_mean([for (final p in group) p.relievingInformation]).padLeft(13)}'
      '${_relievingRankCounts(group).padLeft(30)}',
    );
  }

  stdout.writeln('  substituted family:');
  _writeMap(_countBy(points, (p) => p.familyPair));
  stdout.writeln('  substituted category:');
  _writeMap(_countBy(points, (p) => p.categoryPair));
}

Map<String, int> _countBy(List<_Point> points, String Function(_Point) key) {
  final counts = <String, int>{};
  for (final point in points) {
    final label = key(point);
    counts[label] = (counts[label] ?? 0) + 1;
  }
  return counts;
}

String _relievingRankCounts(List<_Point> points) => [
  for (final rank in RealizationRank.values)
    if (points.any((p) => p.relievingRank == rank))
      '${rank.id.toLowerCase()} '
          '${points.where((p) => p.relievingRank == rank).length}',
].join(', ');

String _rankCounts(List<_Point> points) => [
  for (final rank in RealizationRank.values)
    if (points.any((p) => p.pressuredRank == rank))
      '${rank.id.toLowerCase()} '
          '${points.where((p) => p.pressuredRank == rank).length}',
].join(', ');

String _mean(List<double> values) => values.isEmpty
    ? '-'
    : (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(4);

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
          '(${(100 * numerator / denominator).toStringAsFixed(0)}%)';

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

class _Point {
  final double pressuredP;
  final double relievingP;
  final RealizationRank pressuredRank;
  final RealizationRank relievingRank;
  final double pressuredRetention;
  final double relievingRetention;
  final double pressuredInformation;
  final double relievingInformation;
  final bool pressuredInBand;
  final bool relievingInBand;
  final bool pressuredFullyEligible;
  final bool relievingFullyEligible;
  final String familyPair;
  final String categoryPair;
  final bool outranksPressured;
  final bool taken;
  final bool managed;
  final bool advanced;

  const _Point({
    required this.pressuredP,
    required this.relievingP,
    required this.pressuredRank,
    required this.relievingRank,
    required this.pressuredRetention,
    required this.relievingRetention,
    required this.pressuredInformation,
    required this.relievingInformation,
    required this.pressuredInBand,
    required this.relievingInBand,
    required this.pressuredFullyEligible,
    required this.relievingFullyEligible,
    required this.familyPair,
    required this.categoryPair,
    required this.outranksPressured,
    required this.taken,
    required this.managed,
    required this.advanced,
  });

  double get readinessGap => relievingP - pressuredP;
  bool get isReady => readinessGap >= 0;

  /// Whether a successful attempt could move the relieving frontier.
  bool get hasOpportunity => relievingRank == RealizationRank.advancing;

  /// Whether relief does not step back from the pressured frontier position.
  bool get holdsRank => relievingRank.index >= pressuredRank.index;

  bool get wasUseful => taken && (managed || advanced);

  /// Whether the filter actually changed the winner.
  ///
  /// A set-aside whose relieving candidate already outranks the pressured one
  /// removed candidates that were not going to win, so its outcome says
  /// nothing about relief.
  bool get isEffective => !outranksPressured;
}

class _Relief {
  int unrelieved = 0;
  int unready = 0;
  final List<_Point> points = [];

  int get setAsides => points.length;

  void observe(FamilyPacedPipeline pipeline, Trajectory trajectory) {
    unrelieved += pipeline.unrelievedSlots;
    unready += pipeline.unreadySlots;
    for (final setAside in pipeline.setAsides) {
      final pressured = setAside.pressured;
      final relieving = setAside.relieving;
      final slot = setAside.slot < trajectory.slots.length
          ? trajectory.slots[setAside.slot]
          : null;
      final taken = slot != null && slot.chosen == relieving.exercise;
      points.add(
        _Point(
          pressuredP: pressured.prediction.overallP,
          relievingP: relieving.prediction.overallP,
          pressuredRank: pressured.rankKey!.realization,
          relievingRank: relieving.rankKey!.realization,
          pressuredRetention: pressured.rankKey!.retention,
          relievingRetention: relieving.rankKey!.retention,
          pressuredInformation: pressured.rankKey!.information,
          relievingInformation: relieving.rankKey!.information,
          pressuredInBand: pressured.isWithinChallengeBand,
          relievingInBand: relieving.isWithinChallengeBand,
          pressuredFullyEligible:
              pressured.eligibility.tier == EligibilityTier.fullyEligible,
          relievingFullyEligible:
              relieving.eligibility.tier == EligibilityTier.fullyEligible,
          familyPair:
              '${_familyLabel(pressured.exercise)} -> '
              '${_familyLabel(relieving.exercise)}',
          categoryPair: '${_category(pressured)} -> ${_category(relieving)}',
          outranksPressured:
              relieving.rankKey!.compareTo(pressured.rankKey!) > 0,
          taken: taken,
          managed: taken && slot.managedExecution,
          advanced: taken && slot.frontierAdvanced,
        ),
      );
    }
  }

  void absorb(_Relief other) {
    unrelieved += other.unrelieved;
    unready += other.unready;
    points.addAll(other.points);
  }
}
