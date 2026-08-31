import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How quickly hands-together admissions produce coordination evidence.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('archetypes', defaultsTo: 'developing,uneven_hands,advanced')
    ..addOption('seeds', defaultsTo: '10')
    ..addOption('slots', defaultsTo: '60')
    ..addOption('milestones', defaultsTo: '3')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final archetypes = options.option('archetypes')!.split(',');
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final milestones = int.parse(options.option('milestones')!);
  final jobs = <TrajectoryJob>[
    for (final archetype in archetypes)
      for (var seed = 0; seed < seeds; seed++)
        TrajectoryJob(archetypeId: archetype, seed: seed),
  ];
  final buckets = _dealJobs(jobs);
  final batches = await Future.wait([
    for (final bucket in buckets)
      if (bucket.isNotEmpty) Isolate.run(() => _censusFor(bucket, slots)),
  ]);
  final runs = [for (final batch in batches) ...batch]
    ..sort((a, b) {
      final archetype = archetypes
          .indexOf(a.archetype)
          .compareTo(archetypes.indexOf(b.archetype));
      return archetype != 0 ? archetype : a.seed.compareTo(b.seed);
    });

  stdout
    ..writeln(
      'hands-together evidence acquisition, $seeds independent runs x '
      '$slots slots\n'
      '  score P/R/O = scored observations admitted by execution progression,\n'
      '                recovery, or another path\n'
      '  before N     = progression admissions already spent when the Nth\n'
      '                 coordination observation is applied\n'
      '  contexts@3   = distinct HT execution contexts attempted by the third\n'
      '                 observation\n',
    )
    ..writeln(
      '${'archetype'.padRight(15)}${'runs'.padLeft(6)}${'prog'.padLeft(7)}'
      '${'score P'.padLeft(9)}${'silent P'.padLeft(10)}'
      '${'score R'.padLeft(9)}${'score all'.padLeft(11)}'
      '${'silent all'.padLeft(12)}${'max prog'.padLeft(10)}'
      '${'max silent'.padLeft(12)}',
    );
  for (final archetype in archetypes) {
    final group = runs.where((run) => run.archetype == archetype).toList();
    final progression = _sum(group, (run) => run.progression);
    final progressionScored = _sum(group, (run) => run.progressionScored);
    stdout.writeln(
      '${archetype.padRight(15)}${group.length.toString().padLeft(6)}'
      '${progression.toString().padLeft(7)}'
      '${progressionScored.toString().padLeft(9)}'
      '${(progression - progressionScored).toString().padLeft(10)}'
      '${_sum(group, (run) => run.recoveryScored).toString().padLeft(9)}'
      '${_sum(group, (run) => run.scored).toString().padLeft(11)}'
      '${_sum(group, (run) => run.silent).toString().padLeft(12)}'
      '${_max(group, (run) => run.progression).toString().padLeft(10)}'
      '${_max(group, (run) => run.silent).toString().padLeft(12)}',
    );
  }

  stdout
    ..writeln()
    ..writeln('independent runs')
    ..writeln(
      '${'archetype'.padRight(15)}${'seed'.padLeft(5)}${'prog'.padLeft(6)}'
      '${'score'.padLeft(7)}${'silent'.padLeft(8)}${'score P/R/O'.padLeft(14)}'
      '${'before 1'.padLeft(10)}${'before 2'.padLeft(10)}'
      '${'before 3'.padLeft(10)}${'contexts@3'.padLeft(12)}',
    );

  for (final run in runs) {
    stdout.writeln(
      '${run.archetype.padRight(15)}${run.seed.toString().padLeft(5)}'
      '${run.progression.toString().padLeft(6)}'
      '${run.scored.toString().padLeft(7)}'
      '${run.silent.toString().padLeft(8)}'
      '${'${run.progressionScored}/${run.recoveryScored}/${run.otherScored}'.padLeft(14)}'
      '${_milestone(run, 0, (event) => event.progression).padLeft(10)}'
      '${_milestone(run, 1, (event) => event.progression).padLeft(10)}'
      '${_milestone(run, 2, (event) => event.progression).padLeft(10)}'
      '${_milestone(run, 2, (event) => event.contexts).padLeft(12)}',
    );
  }

  stdout
    ..writeln()
    ..writeln(
      'first $milestones coordination observations per independent run\n'
      '  prediction -> posterior brackets the applied coordination update\n',
    )
    ..writeln(
      '${'archetype'.padRight(15)}${'seed'.padLeft(5)}${'obs'.padLeft(5)}'
      '${'slot'.padLeft(6)} ${'admitted by'.padRight(22)}${'prog'.padLeft(6)}'
      '${'silent'.padLeft(8)}${'contexts'.padLeft(10)}'
      '${'prediction'.padLeft(12)}${'posterior'.padLeft(12)}'
      '${'reading'.padLeft(10)}${'weight'.padLeft(9)}',
    );
  for (final run in runs) {
    for (final event in run.events.take(milestones)) {
      stdout.writeln(
        '${run.archetype.padRight(15)}${run.seed.toString().padLeft(5)}'
        '${event.observation.toString().padLeft(5)}'
        '${event.slot.toString().padLeft(6)} '
        '${event.bypass.padRight(22)}'
        '${event.progression.toString().padLeft(6)}'
        '${event.silent.toString().padLeft(8)}'
        '${event.contexts.toString().padLeft(10)}'
        '${event.prediction.toStringAsFixed(3).padLeft(12)}'
        '${event.posterior.toStringAsFixed(3).padLeft(12)}'
        '${event.reading.toStringAsFixed(3).padLeft(10)}'
        '${event.weight.toStringAsFixed(1).padLeft(9)}',
      );
    }
  }
}

List<List<TrajectoryJob>> _dealJobs(List<TrajectoryJob> jobs) {
  final buckets = List.generate(
    Platform.numberOfProcessors,
    (_) => <TrajectoryJob>[],
  );
  for (final (index, job) in jobs.indexed) {
    buckets[index % buckets.length].add(job);
  }
  return buckets;
}

int _sum(List<_Run> runs, int Function(_Run run) value) =>
    runs.fold(0, (sum, run) => sum + value(run));

int _max(List<_Run> runs, int Function(_Run run) value) =>
    runs.fold(0, (maximum, run) => value(run) > maximum ? value(run) : maximum);

String _milestone(
  _Run run,
  int index,
  int Function(_EvidenceEvent event) value,
) => run.events.length <= index ? '-' : '${value(run.events[index])}';

class _Run {
  final String archetype;
  final int seed;
  final int progression;
  final int scored;
  final int silent;
  final int progressionScored;
  final int recoveryScored;
  final int otherScored;
  final List<_EvidenceEvent> events;

  const _Run({
    required this.archetype,
    required this.seed,
    required this.progression,
    required this.scored,
    required this.silent,
    required this.progressionScored,
    required this.recoveryScored,
    required this.otherScored,
    required this.events,
  });
}

class _EvidenceEvent {
  final int observation;
  final int slot;
  final String bypass;
  final int progression;
  final int silent;
  final int contexts;
  final double prediction;
  final double posterior;
  final double reading;
  final double weight;

  const _EvidenceEvent({
    required this.observation,
    required this.slot,
    required this.bypass,
    required this.progression,
    required this.silent,
    required this.contexts,
    required this.prediction,
    required this.posterior,
    required this.reading,
    required this.weight,
  });
}

List<_Run> _censusFor(List<TrajectoryJob> jobs, int slots) {
  const model = LearnerModel();
  final runs = <_Run>[];

  for (final job in jobs) {
    final bySlot = <int, LearnerState>{};
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
      observeState: (slot, state) => bySlot[slot] = state.copy(),
    );
    final contexts = <ExecutionContext>{};
    final events = <_EvidenceEvent>[];
    var progression = 0;
    var scored = 0;
    var silent = 0;
    var progressionScored = 0;
    var recoveryScored = 0;
    var otherScored = 0;

    for (final slot in trajectory.slots) {
      final exercise = slot.chosen;
      if (exercise.conditions.hands != HandConfiguration.together) continue;
      final bypass = slot.winner.challengeBypass;
      if (bypass == ChallengeBypass.executionProgression) progression++;
      contexts.add(executionContextOf(exercise));

      final reading = slot.outcome.coordination;
      if (reading == null) {
        silent++;
        continue;
      }
      scored++;
      switch (bypass) {
        case ChallengeBypass.executionProgression:
          progressionScored++;
        case ChallengeBypass.recovery:
          recoveryScored++;
        default:
          otherScored++;
      }

      final state = bySlot[slot.index]!;
      final prediction = model.coordinationProbability(state, exercise);
      final weights = evidenceWeightsFor(exercise, slot.outcome);
      final stateAfter = state.copy();
      model.applyOutcome(
        state: stateAfter,
        exercise: exercise,
        outcome: slot.outcome,
        weights: weights,
        prediction: model.predict(state, exercise, at: slot.at),
        at: slot.at,
      );
      events.add(
        _EvidenceEvent(
          observation: scored,
          slot: slot.index,
          bypass: bypass?.id ?? 'ordinary band',
          progression: progression,
          silent: silent,
          contexts: contexts.length,
          prediction: prediction,
          posterior: model.coordinationProbability(stateAfter, exercise),
          reading: reading,
          weight: weights[Competency.handsTogetherCoordination],
        ),
      );
    }

    runs.add(
      _Run(
        archetype: job.archetypeId,
        seed: job.seed,
        progression: progression,
        scored: scored,
        silent: silent,
        progressionScored: progressionScored,
        recoveryScored: recoveryScored,
        otherScored: otherScored,
        events: events,
      ),
    );
  }
  return runs;
}
