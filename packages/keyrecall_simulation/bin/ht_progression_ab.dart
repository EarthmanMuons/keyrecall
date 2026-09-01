import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

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
      if (bucket.isNotEmpty) Isolate.run(() => _runJobs(bucket, slots)),
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
    'HT coordination-weaker progression A/B, '
    '$seeds independent runs x $slots slots',
  );
  for (final archetype in archetypes) {
    final result = results[archetype] ?? _Comparison();
    stdout
      ..writeln('\n$archetype')
      ..writeln(
        '  ${'metric'.padRight(34)}${'current'.padLeft(12)}'
        '${'suppressed'.padLeft(12)}${'delta'.padLeft(12)}',
      );
    _writeMetrics(result.current, result.suppressed);
    stdout
      ..writeln(
        '  first divergence: ${result.divergedRuns}/${result.runs} runs',
      )
      ..writeln('  first replacement categories:');
    _writeMap(result.firstReplacements);
    stdout.writeln('  current targeted next HT:');
    _writeMap(result.current.targetNextHt);
    stdout.writeln(
      '  current next coordination improved: '
      '${result.current.targetNextCoordinationImproved}/'
      '${result.current.targetNextCoordinationCompared}',
    );
    stdout.writeln(
      '  current targeted coordination gap '
      '${_distribution(result.current.targetGaps)}',
    );
    stdout.writeln('  winner-category delta:');
    _writeDeltaMap(result.current.winners, result.suppressed.winners);
  }
}

void _writeMetrics(_Metrics current, _Metrics suppressed) {
  final rows = <(String, num, num, int)>[
    ('total attempts', current.attempts, suppressed.attempts, 0),
    ('HT attempts', current.htAttempts, suppressed.htAttempts, 0),
    ('HT progression', current.htProgression, suppressed.htProgression, 0),
    ('HT recovery', current.htRecovery, suppressed.htRecovery, 0),
    ('HT ordinary band', current.htOrdinary, suppressed.htOrdinary, 0),
    ('managed HT', current.managedHt, suppressed.managedHt, 0),
    (
      'scored coordination',
      current.scoredCoordination,
      suppressed.scoredCoordination,
      0,
    ),
    (
      'mean coordination surprise',
      current.meanSurprise,
      suppressed.meanSurprise,
      6,
    ),
    (
      'final coordination probability',
      current.meanFinalCoordination,
      suppressed.meanFinalCoordination,
      6,
    ),
    (
      'single-hand attempts',
      current.singleHandAttempts,
      suppressed.singleHandAttempts,
      0,
    ),
    (
      'frontier advances',
      current.frontierAdvances,
      suppressed.frontierAdvances,
      0,
    ),
    (
      'single-hand frontier advances',
      current.singleHandAdvances,
      suppressed.singleHandAdvances,
      0,
    ),
    (
      'distinct materials per run',
      current.meanMaterialBreadth,
      suppressed.meanMaterialBreadth,
      3,
    ),
    ('terminal runs', current.terminalRuns, suppressed.terminalRuns, 0),
    (
      'mean first managed HT slot',
      current.meanFirstManagedHt,
      suppressed.meanFirstManagedHt,
      3,
    ),
    (
      'mean later managed HT gap',
      current.meanManagedHtGap,
      suppressed.meanManagedHtGap,
      3,
    ),
    ('coord-weaker progression', current.targeted, suppressed.targeted, 0),
    ('targeted scored', current.targetedScored, suppressed.targetedScored, 0),
    (
      'targeted silent',
      current.targeted - current.targetedScored,
      suppressed.targeted - suppressed.targetedScored,
      0,
    ),
    (
      'mean targeted surprise',
      current.meanTargetedSurprise,
      suppressed.meanTargetedSurprise,
      6,
    ),
    (
      'targeted managed',
      current.targetedManaged,
      suppressed.targetedManaged,
      0,
    ),
    (
      'targeted frontier advances',
      current.targetedAdvances,
      suppressed.targetedAdvances,
      0,
    ),
    (
      'targeted before managed HT',
      current.meanTargetsBeforeManaged,
      suppressed.meanTargetsBeforeManaged,
      3,
    ),
    (
      'mean slots to next HT',
      current.meanTargetNextHtDelay,
      suppressed.meanTargetNextHtDelay,
      3,
    ),
    (
      'mean slots to managed HT',
      current.meanTargetToManagedDelay,
      suppressed.meanTargetToManagedDelay,
      3,
    ),
    (
      'targeted without later managed HT',
      current.unresolvedTargets,
      suppressed.unresolvedTargets,
      0,
    ),
  ];
  for (final (label, a, b, digits) in rows) {
    stdout.writeln(
      '  ${label.padRight(34)}${_number(a, digits).padLeft(12)}'
      '${_number(b, digits).padLeft(12)}'
      '${_signed(b - a, digits).padLeft(12)}',
    );
  }
}

String _number(num value, int digits) =>
    value.isNaN ? '-' : value.toStringAsFixed(digits);

String _signed(num value, int digits) => value.isNaN
    ? '-'
    : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(digits)}';

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

void _writeDeltaMap(Map<String, int> current, Map<String, int> suppressed) {
  final keys = {...current.keys, ...suppressed.keys};
  final deltas = [
    for (final key in keys)
      MapEntry(key, (suppressed[key] ?? 0) - (current[key] ?? 0)),
  ]..removeWhere((entry) => entry.value == 0);
  deltas.sort((a, b) => b.value.abs().compareTo(a.value.abs()));
  if (deltas.isEmpty) {
    stdout.writeln('    none');
  }
  for (final entry in deltas) {
    stdout.writeln(
      '    ${entry.key.padRight(44)}'
      '${entry.value >= 0 ? '+' : ''}${entry.value}',
    );
  }
}

String _distribution(List<double> values) {
  if (values.isEmpty) return 'none';
  final sorted = [...values]..sort();
  final mean = sorted.reduce((a, b) => a + b) / sorted.length;
  double percentile(double p) => sorted[((sorted.length - 1) * p).round()];
  return 'n=${sorted.length}, min=${sorted.first.toStringAsFixed(3)}, '
      'p50=${percentile(0.5).toStringAsFixed(3)}, '
      'p90=${percentile(0.9).toStringAsFixed(3)}, '
      'max=${sorted.last.toStringAsFixed(3)}, mean=${mean.toStringAsFixed(3)}';
}

Map<String, _Comparison> _runJobs(List<TrajectoryJob> jobs, int slots) {
  final results = <String, _Comparison>{};
  for (final job in jobs) {
    final current = _run(
      job,
      slots,
      const SchedulerPipeline(learner: LearnerModel()),
    );
    final suppressed = _run(
      job,
      slots,
      const _CoordinationWeakerSuppressedPipeline(learner: LearnerModel()),
    );
    final comparison = results.putIfAbsent(job.archetypeId, _Comparison.new);
    comparison.runs++;
    comparison.current.absorb(_measure(current));
    comparison.suppressed.absorb(_measure(suppressed));
    final shared =
        current.trajectory.slots.length < suppressed.trajectory.slots.length
        ? current.trajectory.slots.length
        : suppressed.trajectory.slots.length;
    for (var index = 0; index < shared; index++) {
      final a = current.trajectory.slots[index];
      final b = suppressed.trajectory.slots[index];
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

_Run _run(TrajectoryJob job, int slots, SchedulerPipeline pipeline) {
  LearnerState? lastState;
  final trajectory = runTrajectory(
    player: playerOf(job.archetypeId),
    seed: job.seed,
    materials: allScales,
    slots: slots,
    pipeline: pipeline,
    observeState: (_, state) => lastState = state.copy(),
  );
  final finalState = lastState!;
  if (trajectory.terminal == null && trajectory.slots.isNotEmpty) {
    final slot = trajectory.slots.last;
    pipeline.learner.applyOutcome(
      state: finalState,
      exercise: slot.chosen,
      outcome: slot.outcome,
      weights: evidenceWeightsFor(slot.chosen, slot.outcome),
      prediction: slot.winner.prediction,
      at: slot.at,
    );
  }
  return _Run(trajectory, finalState, pipeline.learner);
}

_Metrics _measure(_Run run) {
  final result = _Metrics();
  result.runs++;
  final managedHtSlots = <int>[];
  final materials = <String>{};
  var targetsSinceManaged = 0;
  for (final (index, slot) in run.trajectory.slots.indexed) {
    result.attempts++;
    materials.add(slot.chosen.material.materialId);
    result.winners.update(
      _winnerCategory(slot),
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    if (slot.frontierAdvanced) result.frontierAdvances++;
    final isHt = slot.chosen.conditions.hands == HandConfiguration.together;
    if (!isHt) {
      result.singleHandAttempts++;
      if (slot.frontierAdvanced) result.singleHandAdvances++;
      continue;
    }

    result.htAttempts++;
    switch (slot.winner.challengeBypass) {
      case ChallengeBypass.executionProgression:
        result.htProgression++;
      case ChallengeBypass.recovery:
        result.htRecovery++;
      case null:
        result.htOrdinary++;
      default:
        result.htOther++;
    }
    final reading = slot.outcome.coordination;
    if (reading != null) {
      result.scoredCoordination++;
      result.surpriseSum += reading - slot.winner.prediction.coordinationP;
    }
    final targeted = _isCoordinationWeakerProgression(slot.winner);
    if (targeted) {
      result.targeted++;
      targetsSinceManaged++;
      result.targetGaps.add(
        slot.winner.prediction.executionP -
            slot.winner.prediction.coordinationP,
      );
      if (reading != null) {
        result.targetedScored++;
        result.targetedSurpriseSum +=
            reading - slot.winner.prediction.coordinationP;
      }
      if (slot.managedExecution) result.targetedManaged++;
      if (slot.frontierAdvanced) result.targetedAdvances++;
      final nextHt = run.trajectory.slots
          .skip(index + 1)
          .where(
            (next) =>
                next.chosen.conditions.hands == HandConfiguration.together,
          );
      if (nextHt.isNotEmpty) {
        final next = nextHt.first;
        result.targetNextHtDelayTotal += next.index - slot.index;
        result.targetNextHtDelayCount++;
        final category = next.winner.challengeBypass?.id ?? 'ordinary band';
        result.targetNextHt.update(
          category,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        result.targetNextCoordinationCompared++;
        if (next.winner.prediction.coordinationP >
            slot.winner.prediction.coordinationP) {
          result.targetNextCoordinationImproved++;
        }
      }
      final nextManagedHt = run.trajectory.slots
          .skip(index + 1)
          .where(
            (next) =>
                next.chosen.conditions.hands == HandConfiguration.together &&
                next.managedExecution,
          );
      if (nextManagedHt.isNotEmpty) {
        result.targetToManagedDelayTotal +=
            nextManagedHt.first.index - slot.index;
        result.targetToManagedDelayCount++;
      }
    }
    if (slot.managedExecution) {
      result.managedHt++;
      managedHtSlots.add(slot.index);
      result.targetsBeforeManagedTotal += targetsSinceManaged;
      result.targetsBeforeManagedCount++;
      targetsSinceManaged = 0;
    }
  }
  result.unresolvedTargets += targetsSinceManaged;
  result.materialBreadthTotal += materials.length;
  if (run.trajectory.terminal != null) result.terminalRuns++;
  if (managedHtSlots.isNotEmpty) {
    result.firstManagedHtSlotTotal += managedHtSlots.first;
    result.firstManagedHtCount++;
    for (var index = 1; index < managedHtSlots.length; index++) {
      result.managedHtGapTotal +=
          managedHtSlots[index] - managedHtSlots[index - 1];
      result.managedHtGapCount++;
    }
  }
  result.finalCoordinationTotal += run.learner.coordinationProbability(
    run.finalState,
    Exercise.linear(
      material: allScales.first,
      hands: HandConfiguration.together,
      octaves: 1,
      direction: ScaleDirection.up,
      tempoBpm: 60,
    ),
  );
  return result;
}

bool _isCoordinationWeakerProgression(CandidateTrace trace) =>
    trace.exercise.conditions.hands == HandConfiguration.together &&
    trace.challengeBypass == ChallengeBypass.executionProgression &&
    trace.prediction.coordinationP < trace.prediction.executionP &&
    trace.prediction.overallP < v1SchedulerConfig.challenge.pMin;

String _winnerCategory(TrajectorySlot slot) =>
    '${slot.chosen.conditions.hands.name}/'
    '${slot.winner.challengeBypass?.id ?? 'ordinary'}';

class _CoordinationWeakerSuppressedPipeline extends SchedulerPipeline {
  const _CoordinationWeakerSuppressedPipeline({required super.learner});

  @override
  ChallengeBypass? challengeBypassFor({
    required LearnerState state,
    required Exercise exercise,
    required Prediction prediction,
    required DateTime at,
    required ChallengeBypass? override,
    required Exercise? recoveryTarget,
    required Exercise? tempoProbe,
    required int supportedAttempts,
    required EligibilityTier eligibility,
    required EligibilityTier? introducibleTier,
    DecisionFacts? facts,
  }) {
    final bypass = super.challengeBypassFor(
      state: state,
      exercise: exercise,
      prediction: prediction,
      at: at,
      override: override,
      recoveryTarget: recoveryTarget,
      tempoProbe: tempoProbe,
      supportedAttempts: supportedAttempts,
      eligibility: eligibility,
      introducibleTier: introducibleTier,
      facts: facts,
    );
    if (bypass != ChallengeBypass.executionProgression ||
        exercise.conditions.hands != HandConfiguration.together ||
        prediction.coordinationP >= prediction.executionP ||
        prediction.overallP >= config.challenge.pMin) {
      return bypass;
    }
    return null;
  }
}

class _Run {
  final Trajectory trajectory;
  final LearnerState finalState;
  final LearnerModel learner;

  const _Run(this.trajectory, this.finalState, this.learner);
}

class _Comparison {
  int runs = 0;
  int divergedRuns = 0;
  final _Metrics current = _Metrics();
  final _Metrics suppressed = _Metrics();
  final Map<String, int> firstReplacements = {};

  void absorb(_Comparison other) {
    runs += other.runs;
    divergedRuns += other.divergedRuns;
    current.absorb(other.current);
    suppressed.absorb(other.suppressed);
    other.firstReplacements.forEach((key, value) {
      firstReplacements[key] = (firstReplacements[key] ?? 0) + value;
    });
  }
}

class _Metrics {
  int runs = 0;
  int attempts = 0;
  int htAttempts = 0;
  int htProgression = 0;
  int htRecovery = 0;
  int htOrdinary = 0;
  int htOther = 0;
  int managedHt = 0;
  int scoredCoordination = 0;
  double surpriseSum = 0;
  double finalCoordinationTotal = 0;
  int singleHandAttempts = 0;
  int frontierAdvances = 0;
  int singleHandAdvances = 0;
  int materialBreadthTotal = 0;
  int terminalRuns = 0;
  int firstManagedHtSlotTotal = 0;
  int firstManagedHtCount = 0;
  int managedHtGapTotal = 0;
  int managedHtGapCount = 0;
  int targeted = 0;
  int targetedScored = 0;
  double targetedSurpriseSum = 0;
  int targetedManaged = 0;
  int targetedAdvances = 0;
  int targetsBeforeManagedTotal = 0;
  int targetsBeforeManagedCount = 0;
  int unresolvedTargets = 0;
  int targetNextCoordinationCompared = 0;
  int targetNextCoordinationImproved = 0;
  int targetNextHtDelayTotal = 0;
  int targetNextHtDelayCount = 0;
  int targetToManagedDelayTotal = 0;
  int targetToManagedDelayCount = 0;
  final List<double> targetGaps = [];
  final Map<String, int> targetNextHt = {};
  final Map<String, int> winners = {};

  double get meanSurprise =>
      scoredCoordination == 0 ? double.nan : surpriseSum / scoredCoordination;
  double get meanFinalCoordination =>
      runs == 0 ? double.nan : finalCoordinationTotal / runs;
  double get meanMaterialBreadth =>
      runs == 0 ? double.nan : materialBreadthTotal / runs;
  double get meanFirstManagedHt => firstManagedHtCount == 0
      ? double.nan
      : firstManagedHtSlotTotal / firstManagedHtCount;
  double get meanManagedHtGap => managedHtGapCount == 0
      ? double.nan
      : managedHtGapTotal / managedHtGapCount;
  double get meanTargetsBeforeManaged => targetsBeforeManagedCount == 0
      ? double.nan
      : targetsBeforeManagedTotal / targetsBeforeManagedCount;
  double get meanTargetedSurprise =>
      targetedScored == 0 ? double.nan : targetedSurpriseSum / targetedScored;
  double get meanTargetNextHtDelay => targetNextHtDelayCount == 0
      ? double.nan
      : targetNextHtDelayTotal / targetNextHtDelayCount;
  double get meanTargetToManagedDelay => targetToManagedDelayCount == 0
      ? double.nan
      : targetToManagedDelayTotal / targetToManagedDelayCount;

  void absorb(_Metrics other) {
    runs += other.runs;
    attempts += other.attempts;
    htAttempts += other.htAttempts;
    htProgression += other.htProgression;
    htRecovery += other.htRecovery;
    htOrdinary += other.htOrdinary;
    htOther += other.htOther;
    managedHt += other.managedHt;
    scoredCoordination += other.scoredCoordination;
    surpriseSum += other.surpriseSum;
    finalCoordinationTotal += other.finalCoordinationTotal;
    singleHandAttempts += other.singleHandAttempts;
    frontierAdvances += other.frontierAdvances;
    singleHandAdvances += other.singleHandAdvances;
    materialBreadthTotal += other.materialBreadthTotal;
    terminalRuns += other.terminalRuns;
    firstManagedHtSlotTotal += other.firstManagedHtSlotTotal;
    firstManagedHtCount += other.firstManagedHtCount;
    managedHtGapTotal += other.managedHtGapTotal;
    managedHtGapCount += other.managedHtGapCount;
    targeted += other.targeted;
    targetedScored += other.targetedScored;
    targetedSurpriseSum += other.targetedSurpriseSum;
    targetedManaged += other.targetedManaged;
    targetedAdvances += other.targetedAdvances;
    targetsBeforeManagedTotal += other.targetsBeforeManagedTotal;
    targetsBeforeManagedCount += other.targetsBeforeManagedCount;
    unresolvedTargets += other.unresolvedTargets;
    targetNextCoordinationCompared += other.targetNextCoordinationCompared;
    targetNextCoordinationImproved += other.targetNextCoordinationImproved;
    targetNextHtDelayTotal += other.targetNextHtDelayTotal;
    targetNextHtDelayCount += other.targetNextHtDelayCount;
    targetToManagedDelayTotal += other.targetToManagedDelayTotal;
    targetToManagedDelayCount += other.targetToManagedDelayCount;
    targetGaps.addAll(other.targetGaps);
    for (final source in [
      (other.targetNextHt, targetNextHt),
      (other.winners, winners),
    ]) {
      source.$1.forEach((key, value) {
        source.$2[key] = (source.$2[key] ?? 0) + value;
      });
    }
  }
}
