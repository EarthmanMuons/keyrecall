import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// When a trajectory already knew that forcing more hands-together work was
/// not paying, and how much it went on to force anyway.
///
/// Aggregates separate the archetypes cleanly, which says a gate is possible
/// but not when it would fire. This walks each trajectory in order and asks,
/// before every hands-together admission by execution progression, what the
/// learner-level evidence looked like at that moment.
///
/// Two candidate reasons to withhold, deliberately kept apart because they mean
/// different things:
///
/// - **adverse**: attempts are scored and read materially below what the
///   coordination channel predicted, so the model is overestimating;
/// - **silent**: attempts are not scored at all, so no bilateral moment is
///   being produced and the competency the bypass is justified by cannot be
///   observed either way.
///
/// Both are learner-scoped, because the measured failure reproduces across
/// fresh contexts rather than accumulating within one.
///
/// Also tracks the predicted coordination itself, because adverse surprise is
/// self-extinguishing: once the estimate catches up the surprise goes to zero,
/// and whether anything durable remains is the question a state-based gate
/// depends on.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('archetypes', defaultsTo: 'developing,uneven_hands,advanced')
    ..addOption('seeds', defaultsTo: '10')
    ..addOption('slots', defaultsTo: '60')
    ..addOption('window', defaultsTo: '5')
    ..addOption('adverse', defaultsTo: '-0.05')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final window = int.parse(options.option('window')!);
  final adverseFloor = double.parse(options.option('adverse')!);
  final archetypes = options.option('archetypes')!.split(',');

  final jobs = <TrajectoryJob>[
    for (final archetype in archetypes)
      for (var seed = 0; seed < seeds; seed++)
        TrajectoryJob(archetypeId: archetype, seed: seed),
  ];
  final workers = Platform.numberOfProcessors;
  final buckets = List.generate(workers, (_) => <TrajectoryJob>[]);
  for (final (index, job) in jobs.indexed) {
    buckets[index % workers].add(job);
  }

  final batches = await Future.wait([
    for (final bucket in buckets)
      if (bucket.isNotEmpty)
        Isolate.run(() => _runsFor(bucket, slots, window, adverseFloor)),
  ]);
  final runs = [for (final batch in batches) ...batch];

  stdout
    ..writeln(
      'what a trajectory knew before each hands-together progression bypass, '
      '$seeds seeds x $slots slots, window $window, '
      'adverse below $adverseFloor\n'
      '  prog     = hands-together admissions by execution progression\n'
      '  adverse  = of those, made after the adverse reason first held\n'
      '  silent   = of those, made after the silent reason first held\n'
      '  either   = of those, made after either first held\n'
      '  at       = median progression admissions before either first held\n'
      '  predict  = mean first and last probability across independent runs\n',
    )
    ..writeln(
      '${'archetype'.padRight(16)}${'runs'.padLeft(6)}${'prog'.padLeft(7)}'
      '${'adverse'.padLeft(9)}${'silent'.padLeft(8)}${'either'.padLeft(8)}'
      '${'at'.padLeft(5)}${'predict first'.padLeft(15)}${'last'.padLeft(8)}',
    );

  for (final archetype in archetypes) {
    final mine = [
      for (final run in runs)
        if (run.archetype == archetype) run,
    ];
    if (mine.isEmpty) continue;
    int total(int Function(_Run) of) =>
        mine.fold(0, (sum, run) => sum + of(run));
    final progression = total((r) => r.progression);
    String share(int count) =>
        progression == 0 ? '-' : '${(100 * count / progression).round()}%';
    final firstFires = [
      for (final run in mine)
        if (run.progressionBeforeEither != null) run.progressionBeforeEither!,
    ]..sort();
    double mean(double Function(_Run) of) =>
        mine.fold<double>(0, (sum, run) => sum + of(run)) / mine.length;

    stdout.writeln(
      '${archetype.padRight(16)}${mine.length.toString().padLeft(6)}'
      '${progression.toString().padLeft(7)}'
      '${share(total((r) => r.afterAdverse)).padLeft(9)}'
      '${share(total((r) => r.afterSilent)).padLeft(8)}'
      '${share(total((r) => r.afterEither)).padLeft(8)}'
      '${(firstFires.isEmpty ? '-' : '${firstFires[firstFires.length ~/ 2]}').padLeft(5)}'
      '${mean((r) => r.firstPredicted).toStringAsFixed(3).padLeft(15)}'
      '${mean((r) => r.lastPredicted).toStringAsFixed(3).padLeft(8)}',
    );
  }
}

/// One trajectory's hands-together history.
class _Run {
  final String archetype;
  final int progression;
  final int afterAdverse;
  final int afterSilent;
  final int afterEither;

  /// How many progression admissions happened before either reason first
  /// held, or null when neither ever did.
  final int? progressionBeforeEither;

  final double firstPredicted;
  final double lastPredicted;

  const _Run({
    required this.archetype,
    required this.progression,
    required this.afterAdverse,
    required this.afterSilent,
    required this.afterEither,
    required this.progressionBeforeEither,
    required this.firstPredicted,
    required this.lastPredicted,
  });
}

List<_Run> _runsFor(
  List<TrajectoryJob> jobs,
  int slots,
  int window,
  double adverseFloor,
) {
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

    final surprises = <double>[];
    final scoredRecently = <bool>[];
    var progression = 0;
    var afterAdverse = 0;
    var afterSilent = 0;
    var afterEither = 0;
    int? progressionBeforeEither;
    var everFired = false;
    double? firstPredicted;
    var lastPredicted = 0.0;

    for (final slot in trajectory.slots) {
      final exercise = slot.chosen;
      if (exercise.conditions.hands != HandConfiguration.together) continue;

      final predicted = model.coordinationProbability(
        bySlot[slot.index]!,
        exercise,
      );
      firstPredicted ??= predicted;
      lastPredicted = predicted;

      // What was known before this admission, not counting it.
      final recent = surprises.length <= window
          ? surprises
          : surprises.sublist(surprises.length - window);
      final adverse =
          recent.length >= 3 &&
          recent.reduce((a, b) => a + b) / recent.length < adverseFloor;
      final silence = scoredRecently.length <= 4
          ? scoredRecently
          : scoredRecently.sublist(scoredRecently.length - 4);
      final silent =
          silence.length >= 4 && silence.where((scored) => !scored).length >= 3;

      if (slot.winner.challengeBypass == ChallengeBypass.executionProgression) {
        progression++;
        if (adverse) afterAdverse++;
        if (silent) afterSilent++;
        if (adverse || silent) {
          afterEither++;
        } else if (!everFired) {
          progressionBeforeEither = progression;
        }
      }
      if (adverse || silent) everFired = true;

      final reading = slot.outcome.coordination;
      scoredRecently.add(reading != null);
      if (reading != null) surprises.add(reading - predicted);
    }

    runs.add(
      _Run(
        archetype: job.archetypeId,
        progression: progression,
        afterAdverse: afterAdverse,
        afterSilent: afterSilent,
        afterEither: afterEither,
        progressionBeforeEither: everFired
            ? progressionBeforeEither ?? 0
            : null,
        firstPredicted: firstPredicted ?? 0,
        lastPredicted: lastPredicted,
      ),
    );
  }

  return runs;
}
