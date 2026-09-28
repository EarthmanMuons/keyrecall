import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// One goal over a long horizon: coverage by family at each checkpoint, and
/// what was practiced in each interval between them.
///
/// Each run is appended to [--out] as it finishes, and a rerun over the same
/// file runs only the runs it does not hold yet.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('scope', defaultsTo: 'keyFluency')
    ..addOption('seeds', defaultsTo: '4')
    ..addOption('sessions', defaultsTo: '50')
    ..addOption('every', defaultsTo: '10', help: 'sessions per checkpoint')
    ..addOption('jobs', defaultsTo: '5')
    ..addOption('out', defaultsTo: 'goal_horizon.jsonl')
    ..addOption(
      'progress',
      allowed: [for (final value in ProgressPreference.values) value.name],
      defaultsTo: v1SchedulerConfig.progress.name,
    );
  final options = parser.parse(arguments);
  final scope = GoalTrajectoryScope.values.byName(options.option('scope')!);
  final sessions = int.parse(options.option('sessions')!);
  final every = int.parse(options.option('every')!);
  final progress = ProgressPreference.values.byName(
    options.option('progress')!,
  );
  final curriculum = _resolved(scope);
  final out = ResumableOutput(File(options.option('out')!), {
    'experiment': 'goal_horizon',
    'format': 1,
    'scope': scope.name,
    'progress': progress.name,
    'sessions': sessions,
    'every': every,
    'slots_per_session': 20,
    'curriculum': '${curriculum.curriculumId}@${curriculum.curriculumVersion}',
    ...modelConfiguration(
      schedulerModelVersion: v1SchedulerConfig
          .withProgress(progress)
          .modelVersion,
    ),
  });
  final done = {for (final record in out.resume()) record['identity']};

  final tasks = [
    for (final player in PlayerArchetypes.all)
      for (var seed = 0; seed < int.parse(options.option('seeds')!); seed++)
        if (!done.contains('${player.id}/$seed'))
          () => _run(scope, player, seed, sessions, every, progress),
  ];
  final stopwatch = Stopwatch()..start();
  var next = 0;
  var completed = 0;
  Future<void> work() async {
    while (next < tasks.length) {
      final task = tasks[next++];
      final record = await Isolate.run(task);
      out.append(record);
      stderr.writeln(
        'completed ${++completed}/${tasks.length} '
        '(${stopwatch.elapsed.inSeconds}s)',
      );
    }
  }

  await Future.wait([
    for (var worker = 0; worker < int.parse(options.option('jobs')!); worker++)
      work(),
  ]);
}

Future<Map<String, Object?>> _run(
  GoalTrajectoryScope scope,
  SyntheticPlayer player,
  int seed,
  int sessions,
  int every,
  ProgressPreference progress,
) async {
  final resolved = _resolved(scope);
  final checkpoints = <Map<String, Object?>>[];
  final run = await runGoalTrajectory(
    scope: scope,
    player: player,
    seed: seed,
    sessions: sessions,
    progress: progress,
    afterSession: (sessionIndex, slots, session) {
      if ((sessionIndex + 1) % every != 0) return;
      final evaluated = const PracticeScopeEvaluator().evaluate(
        scope: resolved,
        state: session.state,
        journal: session.journal,
        learner: session.learner,
        at: DateTime.utc(2026).add(Duration(days: sessionIndex + 1, hours: 23)),
      );
      int coveredIn(String familyId) => evaluated.requirements
          .where(
            (state) =>
                state.resolved.isTarget &&
                state.isCovered &&
                state.resolved.material.familyId == familyId,
          )
          .length;
      checkpoints.add({
        'sessions': sessionIndex + 1,
        'slots': slots,
        'covered': evaluated.coverage.coveredTargets,
        'targets': evaluated.coverage.targetCount,
        'scales': coveredIn(TechnicalMaterial.scaleFamilyId),
        'arpeggios': coveredIn(TechnicalMaterial.arpeggioFamilyId),
      });
    },
  );

  double share(
    Iterable<GoalTrajectorySelection> picks,
    bool Function(GoalTrajectorySelection) test,
  ) => picks.isEmpty ? 0 : picks.where(test).length / picks.length;
  final intervals = [
    for (var start = 0; start < sessions; start += every)
      (() {
        final picks = run.selections
            .where(
              (pick) => pick.session >= start && pick.session < start + every,
            )
            .toList();
        return {
          'from_session': start,
          'picks': picks.length,
          'target_shaped': share(picks, (pick) => pick.isTargetShaped),
          'arpeggio': share(
            picks,
            (pick) => pick.familyId == TechnicalMaterial.arpeggioFamilyId,
          ),
          'hands_together': share(
            picks,
            (pick) => pick.hands == HandConfiguration.together,
          ),
          'two_octaves': share(picks, (pick) => pick.octaves >= 2),
          'up_down': share(
            picks,
            (pick) => pick.direction == ExerciseDirection.upDown,
          ),
          'unguided': share(picks, (pick) => !pick.guidance.isMaterialSupplied),
          'cued': share(picks, (pick) => pick.guidance.concurrentPitchCues),
        };
      })(),
  ];

  return {
    'identity': '${player.id}/$seed',
    'player': player.id,
    'seed': seed,
    'targets': run.targetCount,
    'covered': run.finalCovered,
    'milestones': {
      for (final fraction in [0.25, 0.5, 0.75, 1.0])
        '$fraction': run.slotCovering(fraction),
    },
    'caught_up': run.sessions.where((end) => end == SessionEnd.caughtUp).length,
    'blocked': run.sessions.where((end) => end == SessionEnd.blocked).length,
    'checkpoints': checkpoints,
    'intervals': intervals,
    'first': {
      'hands_together': run.firstSlotWhere(
        (pick) => pick.hands == HandConfiguration.together,
      ),
      'two_octaves': run.firstSlotWhere((pick) => pick.octaves >= 2),
      'beyond_two_octaves': run.firstSlotWhere((pick) => pick.octaves > 2),
      'up_down': run.firstSlotWhere(
        (pick) => pick.direction == ExerciseDirection.upDown,
      ),
      'depth_3': run.firstSlotWhere((pick) => depthOf(pick) == 3),
      'depth_3_demonstrated': run.firstSlotWhere(
        (pick) => depthOf(pick) == 3 && demonstrates(pick),
      ),
    },
    'depth': [
      for (final interval in realizationDepthOf(
        run.selections,
        sessions: sessions,
        every: every,
      ))
        interval.toJson(),
    ],
  };
}

ResolvedPracticeScope _resolved(GoalTrajectoryScope scope) {
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];
  final plan = scope.plan.resolve(catalog) as ResolvedPlan;
  return (PracticeScopeResolver().resolve(
            goal: plan.goal,
            focus: plan.focus,
            catalog: catalog,
            instrument: InstrumentProfile(),
          )
          as ValidPracticeScope)
      .scope;
}
