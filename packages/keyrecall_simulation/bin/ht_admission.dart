import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What stands between a coordination transition and a contest, per archetype.
///
/// [isCoordinationTransition] is evaluated for every candidate whatever its
/// tier, so a candidate carrying the term is one a coordination-transition
/// admission path would consider. Walking those says which stage refuses them,
/// and whether a material-supplied realization is among them at all: a path
/// that admits only supplied candidates is inert wherever generation offers
/// none.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '40')
    ..addOption('slots', defaultsTo: '60')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);

  // The same deal as the sweep: trajectories are independent and deterministic
  // in the archetype and seed, dealt round robin so one expensive archetype
  // does not gate an isolate.
  final stopwatch = Stopwatch()..start();
  final workers = Platform.numberOfProcessors;
  final buckets = List.generate(workers, (_) => <_Job>[]);
  var next = 0;
  for (final player in PlayerArchetypes.all) {
    for (var seed = 0; seed < seeds; seed++) {
      buckets[next++ % workers].add(_Job(archetype: player.id, seed: seed));
    }
  }

  final running = [
    for (final bucket in buckets)
      if (bucket.isNotEmpty) Isolate.run(() => _countsFor(bucket, slots)),
  ];
  final batches = await Future.wait(running);

  final totals = <String, _Counts>{};
  for (final batch in batches) {
    batch.forEach((archetype, counts) {
      totals.update(
        archetype,
        (into) => into..absorb(counts),
        ifAbsent: () => counts,
      );
    });
  }

  stdout.writeln(
    'coordination-transition candidates, $seeds seeds x $slots slots, '
    '${running.length} isolates in ${stopwatch.elapsed.inSeconds}s\n'
    '  slots = slots where any candidate carried the transition term\n'
    '  supp  = of those, slots offering a material-supplied realization\n'
    '  elig  = slots where one was already fully eligible\n'
    '  admit = slots where one already survived challenge admission\n'
    '  won   = slots where one was selected\n',
  );

  for (final player in PlayerArchetypes.all) {
    final counts = totals[player.id] ?? _Counts();
    stdout.writeln(
      '${player.id.padRight(20)}'
      'slots ${counts.slots.toString().padLeft(5)}  '
      'supp ${counts.supplied.toString().padLeft(5)}  '
      'elig ${counts.fullyEligible.toString().padLeft(5)}  '
      'admit ${counts.admitted.toString().padLeft(5)}  '
      'won ${counts.won.toString().padLeft(5)}',
    );
    final ordered = counts.reasons.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in ordered) {
      stdout.writeln(
        '  ${entry.key.padRight(40)}'
        '${entry.value.toString().padLeft(7)} candidates, '
        '${(counts.suppliedReasons[entry.key] ?? 0).toString().padLeft(6)} '
        'supplied',
      );
    }
  }
}

class _Job {
  final String archetype;
  final int seed;

  const _Job({required this.archetype, required this.seed});
}

/// Per-archetype tallies, in plain fields so they cross an isolate boundary.
class _Counts {
  int slots = 0;
  int supplied = 0;
  int fullyEligible = 0;
  int admitted = 0;
  int won = 0;
  final Map<String, int> reasons = {};
  final Map<String, int> suppliedReasons = {};

  void absorb(_Counts other) {
    slots += other.slots;
    supplied += other.supplied;
    fullyEligible += other.fullyEligible;
    admitted += other.admitted;
    won += other.won;
    other.reasons.forEach((key, value) {
      reasons[key] = (reasons[key] ?? 0) + value;
    });
    other.suppliedReasons.forEach((key, value) {
      suppliedReasons[key] = (suppliedReasons[key] ?? 0) + value;
    });
  }
}

Map<String, _Counts> _countsFor(List<_Job> jobs, int slots) {
  final byArchetype = <String, _Counts>{};

  for (final job in jobs) {
    final player = PlayerArchetypes.all.firstWhere(
      (candidate) => candidate.id == job.archetype,
    );
    final counts = byArchetype.putIfAbsent(job.archetype, _Counts.new);
    final trajectory = runTrajectory(
      player: player,
      seed: job.seed,
      materials: allScales,
      slots: slots,
      observeTraces: (_, traces) {
        final transitions = [
          for (final trace in traces)
            if (trace.terms.coordinationTransition) trace,
        ];
        if (transitions.isEmpty) return;

        counts.slots++;
        if (transitions.any(
          (trace) => trace.exercise.guidance.isMaterialSupplied,
        )) {
          counts.supplied++;
        }
        if (transitions.any(
          (trace) => trace.eligibility.tier == EligibilityTier.fullyEligible,
        )) {
          counts.fullyEligible++;
        }
        if (transitions.any((trace) => trace.challengeSurvived)) {
          counts.admitted++;
        }

        for (final trace in transitions) {
          final code = trace.eligibility.code.id;
          counts.reasons[code] = (counts.reasons[code] ?? 0) + 1;
          if (trace.exercise.guidance.isMaterialSupplied) {
            counts.suppliedReasons[code] =
                (counts.suppliedReasons[code] ?? 0) + 1;
          }
        }
      },
    );

    for (final slot in trajectory.slots) {
      if (slot.winner.terms.coordinationTransition) counts.won++;
    }
  }

  return byArchetype;
}
