import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How decision cost grows with history: the seeded demo practice run to
/// [attempts] decisions against a file store, reported per [bucket] decisions.
///
/// The workload is deterministic and the timings are not, so compare series
/// taken on one machine and build mode.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('attempts', defaultsTo: '5000')
    ..addOption('bucket', defaultsTo: '500');
  final options = parser.parse(arguments);
  final attempts = int.parse(options.option('attempts')!);
  final bucket = int.parse(options.option('bucket')!);

  final sessions = <DemoSession>[];
  var planned = 0;
  for (final session in demoSessions(
    from: demoHistoryStart,
    until: demoHistoryStart.add(Duration(days: attempts)),
  )) {
    if (planned >= attempts) break;
    sessions.add(session);
    planned += session.slots;
  }

  final root = Directory.systemTemp.createTempSync('demo_scaling');
  final files = FilePracticeStore(root);
  final profile = Profile(
    id: 'demo',
    displayName: 'Demo',
    createdAt: demoHistoryStart,
    placement: PlayerArchetypes.developing.placement,
  );
  final pipeline = _TimedPipeline();
  final rows = <_Bucket>[_Bucket()];

  stdout.writeln(
    [
      'decisions',
      'scheduler_p50_ms',
      'scheduler_p95_ms',
      'decision_p50_ms',
      'decision_p95_ms',
      'candidates',
      'execution_contexts',
      'started_exercises',
      'journal',
      'open_ms',
      'rss_mb',
      'max_rss_mb',
    ].join('\t'),
  );
  final stopwatch = Stopwatch()..start();
  try {
    await practiceDemoHistory(
      store: files.boundTo(await files.lifetimeOf(profile.id)),
      profile: profile,
      player: PlayerArchetypes.developing,
      materials: allPracticeMaterials,
      sessions: sessions,
      pipeline: pipeline,
      onOpen: (elapsed) => rows.last.opens.add(elapsed),
      onDecision: (session, elapsed) {
        final row = rows.last
          ..decisions.add(elapsed)
          ..scheduling.add(pipeline.last)
          ..candidates.add(pipeline.candidates);
        if (row.decisions.length < bucket) return;
        final done = rows.length * bucket;
        stdout.writeln(row.summary(done, session));
        stderr.writeln('$done decisions (${stopwatch.elapsed.inSeconds}s)');
        rows.add(_Bucket());
      },
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}

class _Bucket {
  final decisions = <Duration>[];
  final scheduling = <Duration>[];
  final candidates = <int>[];
  final opens = <Duration>[];

  String summary(int done, PracticeSession session) {
    final history = attemptHistoryOfRecords(session.journal.records);
    return [
      done,
      _ms(_percentile(scheduling, 0.5)),
      _ms(_percentile(scheduling, 0.95)),
      _ms(_percentile(decisions, 0.5)),
      _ms(_percentile(decisions, 0.95)),
      (candidates.reduce((a, b) => a + b) / candidates.length).round(),
      session.state.materialExecution.length,
      history.startedExercises.length,
      session.journal.length,
      opens.isEmpty ? '' : _ms(opens.reduce((a, b) => a + b) ~/ opens.length),
      ProcessInfo.currentRss ~/ (1 << 20),
      ProcessInfo.maxRss ~/ (1 << 20),
    ].join('\t');
  }

  static Duration _percentile(List<Duration> values, double p) {
    final sorted = [...values]..sort();
    return sorted[math.min(sorted.length - 1, (p * sorted.length).floor())];
  }

  static String _ms(Duration value) =>
      (value.inMicroseconds / 1000).toStringAsFixed(1);
}

class _TimedPipeline extends SchedulerPipeline {
  final Stopwatch _watch = Stopwatch();
  Duration last = Duration.zero;
  int candidates = 0;

  _TimedPipeline() : super(learner: const LearnerModel());

  @override
  ({
    SelectionResult result,
    bool guidanceProbeAvailable,
    bool guidanceProbeSelected,
  })
  evaluateSlot({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    AttemptHistory? history,
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
    UncoveredTargets uncoveredTargets = UncoveredTargets.none,
    bool diagnose = true,
  }) {
    this.candidates = candidates.length;
    _watch
      ..reset()
      ..start();
    final slot = super.evaluateSlot(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      history: history,
      practiceEntryPolicy: practiceEntryPolicy,
      emphasis: emphasis,
      uncoveredTargets: uncoveredTargets,
      diagnose: diagnose,
    );
    last = _watch.elapsed;
    return slot;
  }
}
