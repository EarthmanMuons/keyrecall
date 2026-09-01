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
  final results = <String, _Comparison>{};
  for (final batch in batches) {
    batch.forEach((archetype, comparison) {
      results.update(
        archetype,
        (total) => total..absorb(comparison),
        ifAbsent: () => comparison,
      );
    });
  }

  stdout.writeln(
    'realization-family pacing A/B, $seeds independent runs x $slots slots, '
    'window ${pacing.window}, floor ${pacing.shareFloor}, '
    'min ${pacing.minFamilyAttempts}, set aside at ${pacing.setAsideAt}, '
    'ready alternative required ${pacing.requireReadyAlternative}',
  );
  for (final archetype in archetypes) {
    final result = results[archetype] ?? _Comparison();
    stdout
      ..writeln('\n$archetype')
      ..writeln(
        '  ${'metric'.padRight(32)}${'current'.padLeft(12)}'
        '${'paced'.padLeft(12)}${'delta'.padLeft(12)}',
      );
    _writeMetrics(result.current, result.paced);
    stdout.writeln('  per-run distributions (median / p90 / max)');
    _writeDistributions(result.current, result.paced);
    stdout
      ..writeln(
        '  set-aside slots: ${result.paced.setAsideSlots}; '
        'nothing to relieve: ${result.paced.unrelievedSlots}; '
        'no ready alternative: ${result.paced.unreadySlots}',
      )
      ..writeln(
        '  first divergence: ${result.divergedRuns}/${result.runs} runs',
      )
      ..writeln('  first replacement categories:');
    _writeMap(result.firstReplacements);
  }
}

void _writeMetrics(_Metrics current, _Metrics paced) {
  final rows = <(String, num, num, int)>[
    ('total attempts', current.attempts, paced.attempts, 0),
    for (final family in _Family.values)
      (
        '${family.label} share',
        current.familyShare(family),
        paced.familyShare(family),
        1,
      ),
    ('HT attempts', current.htAttempts, paced.htAttempts, 0),
    ('managed HT', current.managedHt, paced.managedHt, 0),
    ('HT progression', current.htProgression, paced.htProgression, 0),
    ('HT recovery', current.htRecovery, paced.htRecovery, 0),
    ('HT ordinary band', current.htOrdinary, paced.htOrdinary, 0),
    (
      'single-hand attempts',
      current.singleHandAttempts,
      paced.singleHandAttempts,
      0,
    ),
    (
      'single-hand recovery',
      current.singleHandRecovery,
      paced.singleHandRecovery,
      0,
    ),
    ('frontier advances', current.frontierAdvances, paced.frontierAdvances, 0),
    (
      'single-hand frontier advances',
      current.singleHandAdvances,
      paced.singleHandAdvances,
      0,
    ),
    ('HT frontier advances', current.htAdvances, paced.htAdvances, 0),
    (
      'scored coordination',
      current.scoredCoordination,
      paced.scoredCoordination,
      0,
    ),
    (
      'distinct materials per run',
      current.meanMaterialBreadth,
      paced.meanMaterialBreadth,
      3,
    ),
    ('runs with no HT', current.runsWithoutHt, paced.runsWithoutHt, 0),
    ('terminal runs', current.terminalRuns, paced.terminalRuns, 0),
    ('mean first HT slot', current.meanFirstHt, paced.meanFirstHt, 3),
    (
      'mean slots to single hand',
      current.meanSlotsToSingleHand,
      paced.meanSlotsToSingleHand,
      3,
    ),
  ];
  for (final (label, a, b, digits) in rows) {
    stdout.writeln(
      '  ${label.padRight(32)}${_number(a, digits).padLeft(12)}'
      '${_number(b, digits).padLeft(12)}'
      '${_signed(b - a, digits).padLeft(12)}',
    );
  }
}

void _writeDistributions(_Metrics current, _Metrics paced) {
  final rows = <(String, List<int>, List<int>, int?)>[
    ('max HT in 20 slots', current.maxHt20, paced.maxHt20, 20),
    (
      'max unmanaged HT in 20',
      current.maxUnmanagedHt20,
      paced.maxUnmanagedHt20,
      20,
    ),
    ('longest consecutive HT', current.longestHt, paced.longestHt, null),
    (
      'longest unmanaged HT run',
      current.longestUnmanagedHt,
      paced.longestUnmanagedHt,
      null,
    ),
    (
      'fewest families in 20 slots',
      current.minFamilies20,
      paced.minFamilies20,
      null,
    ),
    ('HT motion switches', current.motionSwitches, paced.motionSwitches, null),
  ];
  for (final (label, a, b, window) in rows) {
    stdout.writeln(
      '    ${label.padRight(30)}'
      '${_distribution(a, window: window).padLeft(20)}'
      '${_distribution(b, window: window).padLeft(20)}',
    );
  }
}

String _number(num value, int digits) =>
    value.isNaN ? '-' : value.toStringAsFixed(digits);

String _signed(num value, int digits) => value.isNaN
    ? '-'
    : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(digits)}';

String _distribution(List<int> values, {int? window}) {
  if (values.isEmpty) return '-';
  final sorted = [...values]..sort();
  int percentile(double p) => sorted[((sorted.length - 1) * p).round()];
  String show(int value) => window == null
      ? '$value'
      : '${(100 * value / window).toStringAsFixed(0)}%';
  return '${show(percentile(0.5))}/${show(percentile(0.9))}/'
      '${show(sorted.last)}';
}

void _writeMap(Map<String, int> values) {
  if (values.isEmpty) {
    stdout.writeln('    none');
    return;
  }
  final entries = values.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in entries) {
    stdout.writeln(
      '    ${entry.key.padRight(44)}${entry.value.toString().padLeft(5)}',
    );
  }
}

Map<String, _Comparison> _runJobs(
  List<TrajectoryJob> jobs,
  int slots,
  RealizationFamilyPacingConfig pacing,
) {
  final results = <String, _Comparison>{};
  for (final job in jobs) {
    final pipeline = FamilyPacedPipeline(
      learner: const LearnerModel(),
      pacing: RealizationFamilyPacing(config: pacing),
    );
    final current = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
    );
    final paced = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
      pipeline: pipeline,
    );
    final comparison = results.putIfAbsent(job.archetypeId, _Comparison.new);
    comparison.runs++;
    comparison.current.absorb(_measure(current));
    comparison.paced.absorb(
      _measure(paced)
        ..setAsideSlots = pipeline.setAsides.length
        ..unrelievedSlots = pipeline.unrelievedSlots
        ..unreadySlots = pipeline.unreadySlots,
    );
    final shared = current.slots.length < paced.slots.length
        ? current.slots.length
        : paced.slots.length;
    for (var index = 0; index < shared; index++) {
      final a = current.slots[index];
      final b = paced.slots[index];
      if (a.chosen == b.chosen) continue;
      comparison.divergedRuns++;
      final replacement = '${_winnerCategory(a)} -> ${_winnerCategory(b)}';
      comparison.firstReplacements[replacement] =
          (comparison.firstReplacements[replacement] ?? 0) + 1;
      break;
    }
  }
  return results;
}

_Metrics _measure(Trajectory trajectory) {
  final result = _Metrics();
  result.runs++;
  final slots = trajectory.slots;
  final materials = <String>{};
  HandMotion? previousHtMotion;
  var motionSwitches = 0;
  int? firstHt;
  for (final (index, slot) in slots.indexed) {
    result.attempts++;
    materials.add(slot.chosen.material.materialId);
    final family = _familyOf(slot.chosen);
    result.familyAttempts.update(family, (n) => n + 1, ifAbsent: () => 1);
    final isRecovery = slot.winner.challengeBypass == ChallengeBypass.recovery;
    if (slot.frontierAdvanced) result.frontierAdvances++;
    if (!family.isHandsTogether) {
      result.singleHandAttempts++;
      if (isRecovery) result.singleHandRecovery++;
      if (slot.frontierAdvanced) result.singleHandAdvances++;
      continue;
    }

    result.htAttempts++;
    firstHt ??= slot.index;
    if (slot.managedExecution) result.managedHt++;
    if (slot.frontierAdvanced) result.htAdvances++;
    if (slot.outcome.coordination != null) result.scoredCoordination++;
    switch (slot.winner.challengeBypass) {
      case ChallengeBypass.executionProgression:
        result.htProgression++;
      case ChallengeBypass.recovery:
        result.htRecovery++;
      case null:
        result.htOrdinary++;
      default:
        break;
    }
    final motion = slot.chosen.conditions.handMotion;
    if (previousHtMotion != null && previousHtMotion != motion) {
      motionSwitches++;
    }
    previousHtMotion = motion;

    if (slot.winner.challengeBypass != ChallengeBypass.executionProgression ||
        slot.managedExecution) {
      continue;
    }
    final nextSingle = slots
        .skip(index + 1)
        .where(
          (candidate) =>
              candidate.chosen.conditions.hands != HandConfiguration.together,
        );
    if (nextSingle.isNotEmpty) {
      result.slotsToSingleHandTotal += nextSingle.first.index - slot.index;
      result.slotsToSingleHandCount++;
    }
  }

  result.materialBreadthTotal += materials.length;
  if (trajectory.terminal != null) result.terminalRuns++;
  if (firstHt == null) {
    result.runsWithoutHt++;
  } else {
    result.firstHtTotal += firstHt;
    result.firstHtCount++;
  }
  result.motionSwitches.add(motionSwitches);
  result.maxHt20.add(_maxInWindow(slots, 20, _isHt));
  result.maxUnmanagedHt20.add(_maxInWindow(slots, 20, _isUnmanagedHt));
  result.longestHt.add(_longestRun(slots, _isHt));
  result.longestUnmanagedHt.add(_longestRun(slots, _isUnmanagedHt));
  result.minFamilies20.add(_minFamiliesInWindow(slots, 20));
  return result;
}

bool _isHt(TrajectorySlot slot) =>
    slot.chosen.conditions.hands == HandConfiguration.together;

bool _isUnmanagedHt(TrajectorySlot slot) =>
    _isHt(slot) && !slot.managedExecution;

int _maxInWindow(
  List<TrajectorySlot> slots,
  int width,
  bool Function(TrajectorySlot) matches,
) {
  if (slots.isEmpty) return 0;
  final actualWidth = width < slots.length ? width : slots.length;
  var count = slots.take(actualWidth).where(matches).length;
  var maximum = count;
  for (var index = actualWidth; index < slots.length; index++) {
    if (matches(slots[index - actualWidth])) count--;
    if (matches(slots[index])) count++;
    if (count > maximum) maximum = count;
  }
  return maximum;
}

int _longestRun(
  List<TrajectorySlot> slots,
  bool Function(TrajectorySlot) matches,
) {
  var longest = 0;
  var current = 0;
  for (final slot in slots) {
    current = matches(slot) ? current + 1 : 0;
    if (current > longest) longest = current;
  }
  return longest;
}

int _minFamiliesInWindow(List<TrajectorySlot> slots, int width) {
  if (slots.isEmpty) return 0;
  final actualWidth = width < slots.length ? width : slots.length;
  var minimum = _Family.values.length;
  for (var start = 0; start + actualWidth <= slots.length; start++) {
    final families = {
      for (final slot in slots.skip(start).take(actualWidth))
        _familyOf(slot.chosen),
    };
    if (families.length < minimum) minimum = families.length;
  }
  return minimum;
}

_Family _familyOf(Exercise exercise) => switch (exercise.conditions.hands) {
  HandConfiguration.right => _Family.right,
  HandConfiguration.left => _Family.left,
  HandConfiguration.together =>
    exercise.conditions.handMotion == HandMotion.contrary
        ? _Family.htContrary
        : _Family.htParallel,
};

String _winnerCategory(TrajectorySlot slot) =>
    '${_familyOf(slot.chosen).label}/'
    '${slot.winner.challengeBypass?.id ?? 'ordinary'}';

enum _Family {
  right('right hand', false),
  left('left hand', false),
  htParallel('HT parallel', true),
  htContrary('HT contrary', true);

  const _Family(this.label, this.isHandsTogether);

  final String label;
  final bool isHandsTogether;
}

class _Comparison {
  int runs = 0;
  int divergedRuns = 0;
  final _Metrics current = _Metrics();
  final _Metrics paced = _Metrics();
  final Map<String, int> firstReplacements = {};

  void absorb(_Comparison other) {
    runs += other.runs;
    divergedRuns += other.divergedRuns;
    current.absorb(other.current);
    paced.absorb(other.paced);
    other.firstReplacements.forEach((key, value) {
      firstReplacements[key] = (firstReplacements[key] ?? 0) + value;
    });
  }
}

class _Metrics {
  int runs = 0;
  int attempts = 0;
  int htAttempts = 0;
  int managedHt = 0;
  int htProgression = 0;
  int htRecovery = 0;
  int htOrdinary = 0;
  int htAdvances = 0;
  int singleHandAttempts = 0;
  int singleHandRecovery = 0;
  int singleHandAdvances = 0;
  int frontierAdvances = 0;
  int scoredCoordination = 0;
  int materialBreadthTotal = 0;
  int terminalRuns = 0;
  int runsWithoutHt = 0;
  int firstHtTotal = 0;
  int firstHtCount = 0;
  int slotsToSingleHandTotal = 0;
  int slotsToSingleHandCount = 0;
  int setAsideSlots = 0;
  int unrelievedSlots = 0;
  int unreadySlots = 0;
  final Map<_Family, int> familyAttempts = {};
  final List<int> maxHt20 = [];
  final List<int> maxUnmanagedHt20 = [];
  final List<int> longestHt = [];
  final List<int> longestUnmanagedHt = [];
  final List<int> minFamilies20 = [];
  final List<int> motionSwitches = [];

  double familyShare(_Family family) => attempts == 0
      ? double.nan
      : 100 * (familyAttempts[family] ?? 0) / attempts;
  double get meanMaterialBreadth =>
      runs == 0 ? double.nan : materialBreadthTotal / runs;
  double get meanFirstHt =>
      firstHtCount == 0 ? double.nan : firstHtTotal / firstHtCount;
  double get meanSlotsToSingleHand => slotsToSingleHandCount == 0
      ? double.nan
      : slotsToSingleHandTotal / slotsToSingleHandCount;

  void absorb(_Metrics other) {
    runs += other.runs;
    attempts += other.attempts;
    htAttempts += other.htAttempts;
    managedHt += other.managedHt;
    htProgression += other.htProgression;
    htRecovery += other.htRecovery;
    htOrdinary += other.htOrdinary;
    htAdvances += other.htAdvances;
    singleHandAttempts += other.singleHandAttempts;
    singleHandRecovery += other.singleHandRecovery;
    singleHandAdvances += other.singleHandAdvances;
    frontierAdvances += other.frontierAdvances;
    scoredCoordination += other.scoredCoordination;
    materialBreadthTotal += other.materialBreadthTotal;
    terminalRuns += other.terminalRuns;
    runsWithoutHt += other.runsWithoutHt;
    firstHtTotal += other.firstHtTotal;
    firstHtCount += other.firstHtCount;
    slotsToSingleHandTotal += other.slotsToSingleHandTotal;
    slotsToSingleHandCount += other.slotsToSingleHandCount;
    setAsideSlots += other.setAsideSlots;
    unrelievedSlots += other.unrelievedSlots;
    unreadySlots += other.unreadySlots;
    other.familyAttempts.forEach((key, value) {
      familyAttempts[key] = (familyAttempts[key] ?? 0) + value;
    });
    maxHt20.addAll(other.maxHt20);
    maxUnmanagedHt20.addAll(other.maxUnmanagedHt20);
    longestHt.addAll(other.longestHt);
    longestUnmanagedHt.addAll(other.longestUnmanagedHt);
    minFamilies20.addAll(other.minFamilies20);
    motionSwitches.addAll(other.motionSwitches);
  }
}
