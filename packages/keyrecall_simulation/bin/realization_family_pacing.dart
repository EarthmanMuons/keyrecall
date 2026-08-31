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
      if (bucket.isNotEmpty) Isolate.run(() => _runJobs(bucket, slots)),
  ]);
  final results = <String, _Counts>{};
  for (final batch in batches) {
    batch.forEach((archetype, counts) {
      results.update(
        archetype,
        (total) => total..absorb(counts),
        ifAbsent: () => counts,
      );
    });
  }

  stdout.writeln(
    'realization-family pacing, $seeds independent runs x $slots slots',
  );
  for (final archetype in archetypes) {
    final counts = results[archetype] ?? _Counts();
    _writeArchetype(archetype, counts);
  }
}

void _writeArchetype(String archetype, _Counts counts) {
  stdout
    ..writeln('\n$archetype')
    ..writeln(
      '${'family'.padRight(14)}${'n'.padLeft(7)}${'share'.padLeft(8)}'
      '${'managed'.padLeft(10)}${'advance'.padLeft(10)}'
      '${'new'.padLeft(8)}${'prog'.padLeft(8)}${'recov'.padLeft(8)}'
      '${'ordinary'.padLeft(10)}${'contexts/run'.padLeft(14)}'
      '${'surprise'.padLeft(11)}',
    );
  for (final family in _Family.values) {
    final familyCounts = counts.families[family] ?? _FamilyCounts();
    stdout.writeln(
      '${family.label.padRight(14)}${familyCounts.attempts.toString().padLeft(7)}'
      '${_percent(familyCounts.attempts, counts.attempts).padLeft(8)}'
      '${_percent(familyCounts.managed, familyCounts.attempts).padLeft(10)}'
      '${_percent(familyCounts.advanced, familyCounts.attempts).padLeft(10)}'
      '${familyCounts.unmeasured.toString().padLeft(8)}'
      '${familyCounts.progression.toString().padLeft(8)}'
      '${familyCounts.recovery.toString().padLeft(8)}'
      '${familyCounts.ordinary.toString().padLeft(10)}'
      '${_mean(familyCounts.contextsPerRun).padLeft(14)}'
      '${_meanValue(familyCounts.surpriseSum, familyCounts.scored).padLeft(11)}',
    );
  }

  stdout
    ..writeln('  per-run pacing distributions (median / p90 / max)')
    ..writeln(
      '    max HT in 20 slots:          '
      '${_distribution(counts.maxHt20, window: 20)}',
    )
    ..writeln(
      '    max unmanaged HT in 20:      '
      '${_distribution(counts.maxUnmanagedHt20, window: 20)}',
    )
    ..writeln(
      '    max HT in 40 slots:          '
      '${_distribution(counts.maxHt40, window: 40)}',
    )
    ..writeln(
      '    max unmanaged HT in 40:      '
      '${_distribution(counts.maxUnmanagedHt40, window: 40)}',
    )
    ..writeln(
      '    longest consecutive HT:      '
      '${_distribution(counts.longestHt)}',
    )
    ..writeln(
      '    longest consecutive unmanaged HT: '
      '${_distribution(counts.longestUnmanagedHt)}',
    )
    ..writeln(
      '    fewest families in 20 slots: '
      '${_distribution(counts.minFamilies20)}',
    )
    ..writeln(
      '    first HT slot:                '
      '${_distribution(counts.firstHtSlots)}',
    )
    ..writeln(
      '    HT motion switches per run:  '
      '${_distribution(counts.motionSwitches)}',
    )
    ..writeln(
      '  unmanaged HT progression: ${counts.unmanagedProgression}; '
      'no later single-hand work: ${counts.noLaterSingleHand}',
    )
    ..writeln(
      '    slots until single-hand:      '
      '${_distribution(counts.slotsToSingleHand)}',
    )
    ..writeln('    next selected family:');
  _writeMap(counts.nextFamily);
  stdout.writeln('    first HT motion per run:');
  _writeMap(counts.firstHtMotion);
}

String _percent(int numerator, int denominator) {
  if (denominator == 0) return '-';
  return '${(100 * numerator / denominator).toStringAsFixed(1)}%';
}

String _mean(List<int> values) {
  if (values.isEmpty) return '-';
  return (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(1);
}

String _meanValue(double total, int count) =>
    count == 0 ? '-' : (total / count).toStringAsFixed(3);

String _distribution(List<int> values, {int? window}) {
  if (values.isEmpty) return '-';
  final sorted = [...values]..sort();
  int percentile(double p) => sorted[((sorted.length - 1) * p).round()];
  String show(int value) => window == null
      ? '$value'
      : '${(100 * value / window).toStringAsFixed(0)}%';
  return '${show(percentile(0.5))} / ${show(percentile(0.9))} / '
      '${show(sorted.last)}';
}

void _writeMap(Map<String, int> values) {
  if (values.isEmpty) {
    stdout.writeln('      none');
    return;
  }
  final entries = values.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in entries) {
    stdout.writeln(
      '      ${entry.key.padRight(28)}${entry.value.toString().padLeft(5)}',
    );
  }
}

Map<String, _Counts> _runJobs(List<TrajectoryJob> jobs, int slots) {
  final results = <String, _Counts>{};
  for (final job in jobs) {
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
    );
    final counts = results.putIfAbsent(job.archetypeId, _Counts.new);
    _countTrajectory(trajectory, counts);
  }
  return results;
}

void _countTrajectory(Trajectory trajectory, _Counts counts) {
  counts.runs++;
  final slots = trajectory.slots;
  final contexts = <_Family, Set<ExecutionContext>>{};
  HandMotion? previousHtMotion;
  int? firstHt;
  for (final (index, slot) in slots.indexed) {
    counts.attempts++;
    final family = _familyOf(slot.chosen);
    final familyCounts = counts.families.putIfAbsent(family, _FamilyCounts.new);
    familyCounts.attempts++;
    (contexts[family] ??= {}).add(executionContextOf(slot.chosen));
    if (slot.managedExecution) familyCounts.managed++;
    if (slot.frontierAdvanced) familyCounts.advanced++;
    if (slot.realization == RealizationRank.unmeasured) {
      familyCounts.unmeasured++;
    }
    switch (slot.winner.challengeBypass) {
      case ChallengeBypass.executionProgression:
        familyCounts.progression++;
      case ChallengeBypass.recovery:
        familyCounts.recovery++;
      case null:
        familyCounts.ordinary++;
      default:
        familyCounts.otherBypass++;
    }

    if (!family.isHandsTogether) continue;
    firstHt ??= slot.index;
    final reading = slot.outcome.coordination;
    if (reading != null) {
      familyCounts.scored++;
      familyCounts.surpriseSum +=
          reading - slot.winner.prediction.coordinationP;
    }
    final motion = slot.chosen.conditions.handMotion;
    if (previousHtMotion != null && previousHtMotion != motion) {
      counts.motionSwitchesCurrentRun++;
    }
    previousHtMotion = motion;

    if (slot.winner.challengeBypass != ChallengeBypass.executionProgression ||
        slot.managedExecution) {
      continue;
    }
    counts.unmanagedProgression++;
    final later = slots.skip(index + 1);
    if (later.isEmpty) {
      counts.noLaterSingleHand++;
      continue;
    }
    final next = later.first;
    final nextFamily = _familyOf(next.chosen).label;
    counts.nextFamily[nextFamily] = (counts.nextFamily[nextFamily] ?? 0) + 1;
    final nextSingle = later.where(
      (candidate) =>
          candidate.chosen.conditions.hands != HandConfiguration.together,
    );
    if (nextSingle.isEmpty) {
      counts.noLaterSingleHand++;
    } else {
      counts.slotsToSingleHand.add(nextSingle.first.index - slot.index);
    }
  }

  for (final family in _Family.values) {
    counts.families
        .putIfAbsent(family, _FamilyCounts.new)
        .contextsPerRun
        .add(contexts[family]?.length ?? 0);
  }
  if (firstHt != null) {
    counts.firstHtSlots.add(firstHt);
    final firstMotion = slots[firstHt].chosen.conditions.handMotion.name;
    counts.firstHtMotion[firstMotion] =
        (counts.firstHtMotion[firstMotion] ?? 0) + 1;
  }
  counts.motionSwitches.add(counts.motionSwitchesCurrentRun);
  counts.motionSwitchesCurrentRun = 0;
  counts.maxHt20.add(_maxInWindow(slots, 20, _isHt));
  counts.maxUnmanagedHt20.add(_maxInWindow(slots, 20, _isUnmanagedHt));
  counts.maxHt40.add(_maxInWindow(slots, 40, _isHt));
  counts.maxUnmanagedHt40.add(_maxInWindow(slots, 40, _isUnmanagedHt));
  counts.longestHt.add(_longestRun(slots, _isHt));
  counts.longestUnmanagedHt.add(_longestRun(slots, _isUnmanagedHt));
  counts.minFamilies20.add(_minFamiliesInWindow(slots, 20));
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

enum _Family {
  right('right hand', false),
  left('left hand', false),
  htParallel('HT parallel', true),
  htContrary('HT contrary', true);

  const _Family(this.label, this.isHandsTogether);

  final String label;
  final bool isHandsTogether;
}

class _FamilyCounts {
  int attempts = 0;
  int managed = 0;
  int advanced = 0;
  int unmeasured = 0;
  int progression = 0;
  int recovery = 0;
  int ordinary = 0;
  int otherBypass = 0;
  int scored = 0;
  double surpriseSum = 0;
  final List<int> contextsPerRun = [];

  void absorb(_FamilyCounts other) {
    attempts += other.attempts;
    managed += other.managed;
    advanced += other.advanced;
    unmeasured += other.unmeasured;
    progression += other.progression;
    recovery += other.recovery;
    ordinary += other.ordinary;
    otherBypass += other.otherBypass;
    scored += other.scored;
    surpriseSum += other.surpriseSum;
    contextsPerRun.addAll(other.contextsPerRun);
  }
}

class _Counts {
  int runs = 0;
  int attempts = 0;
  int unmanagedProgression = 0;
  int noLaterSingleHand = 0;
  int motionSwitchesCurrentRun = 0;
  final Map<_Family, _FamilyCounts> families = {};
  final List<int> maxHt20 = [];
  final List<int> maxUnmanagedHt20 = [];
  final List<int> maxHt40 = [];
  final List<int> maxUnmanagedHt40 = [];
  final List<int> longestHt = [];
  final List<int> longestUnmanagedHt = [];
  final List<int> minFamilies20 = [];
  final List<int> firstHtSlots = [];
  final List<int> motionSwitches = [];
  final List<int> slotsToSingleHand = [];
  final Map<String, int> nextFamily = {};
  final Map<String, int> firstHtMotion = {};

  void absorb(_Counts other) {
    runs += other.runs;
    attempts += other.attempts;
    unmanagedProgression += other.unmanagedProgression;
    noLaterSingleHand += other.noLaterSingleHand;
    for (final entry in other.families.entries) {
      families.putIfAbsent(entry.key, _FamilyCounts.new).absorb(entry.value);
    }
    maxHt20.addAll(other.maxHt20);
    maxUnmanagedHt20.addAll(other.maxUnmanagedHt20);
    maxHt40.addAll(other.maxHt40);
    maxUnmanagedHt40.addAll(other.maxUnmanagedHt40);
    longestHt.addAll(other.longestHt);
    longestUnmanagedHt.addAll(other.longestUnmanagedHt);
    minFamilies20.addAll(other.minFamilies20);
    firstHtSlots.addAll(other.firstHtSlots);
    motionSwitches.addAll(other.motionSwitches);
    slotsToSingleHand.addAll(other.slotsToSingleHand);
    for (final source in [
      (other.nextFamily, nextFamily),
      (other.firstHtMotion, firstHtMotion),
    ]) {
      source.$1.forEach((key, value) {
        source.$2[key] = (source.$2[key] ?? 0) + value;
      });
    }
  }
}
