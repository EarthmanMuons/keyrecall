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
/// Allocation's share is reported apart: what the host spends after the slot
/// is evaluated, and what folding both logs into waiting counters costs at the
/// history each decision reads, timed again outside the session. `--scheduling`
/// runs the profile under the allocation pilot rather than v1-14.
///
/// The workload is deterministic and the timings are not, so compare series
/// taken on one machine and build mode.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('attempts', defaultsTo: '5000')
    ..addOption('bucket', defaultsTo: '500')
    ..addOption(
      'scheduling',
      allowed: [
        for (final assignment in SchedulingAssignment.values) assignment.id,
      ],
      defaultsTo: SchedulingAssignment.v1_14.id,
    );
  final options = parser.parse(arguments);
  final attempts = int.parse(options.option('attempts')!);
  final bucket = int.parse(options.option('bucket')!);
  final scheduling = SchedulingAssignment.fromId(options.option('scheduling')!);

  final sessions = <DemoSession>[];
  var planned = 0;
  for (final (:start, :slots) in demoSessions(
    from: demoHistoryStart,
    until: demoHistoryStart.add(Duration(days: attempts)),
  )) {
    if (planned >= attempts) break;
    final kept = math.min(slots, attempts - planned);
    sessions.add((start: start, slots: kept));
    planned += kept;
  }

  final root = Directory.systemTemp.createTempSync('demo_scaling');
  final files = FilePracticeStore(root);
  final profile = Profile(
    id: 'demo',
    displayName: 'Demo',
    createdAt: demoHistoryStart,
    placement: PlayerArchetypes.developing.placement,
    schedulingOverride: scheduling,
  );
  final pipeline = _TimedPipeline();
  final host = _TimedHost(pipeline);
  final rows = <_Bucket>[_Bucket()];
  var done = 0;
  PracticeSession? last;

  stdout.writeln(
    [
      'decisions',
      'scheduler_p50_ms',
      'scheduler_p95_ms',
      'allocation_p50_ms',
      'allocation_p95_ms',
      'fold_p50_ms',
      'fold_p95_ms',
      'decision_p50_ms',
      'decision_p95_ms',
      'commit_p50_ms',
      'commit_p95_ms',
      'candidates',
      'execution_contexts',
      'started_exercises',
      'journal',
      'acquisition_attempts',
      'waiting',
      'journal_kb',
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
      scheduler: (_) => host,
      onOpen: (_, elapsed) => rows.last.opens.add(elapsed),
      onCommit: (_, elapsed) => rows.last.commits.add(elapsed),
      onDecision: (session, elapsed) {
        done++;
        last = session;
        final folding = Stopwatch()..start();
        AllocationHistory.of(session.journal, session.acquisitionJournal);
        final row = rows.last
          ..decisions.add(elapsed)
          ..scheduling.add(pipeline.last)
          ..allocation.add(host.last - pipeline.last)
          ..folds.add(folding.elapsed)
          ..candidates.add(pipeline.candidates);
        if (row.decisions.length < bucket) return;
        stdout.writeln(row.summary(done, session, journalFile(root)));
        stderr.writeln('$done decisions (${stopwatch.elapsed.inSeconds}s)');
        rows.add(_Bucket());
      },
    );
    // A short final bucket, or a run that ended before its count.
    if (rows.last.decisions.isNotEmpty) {
      stdout.writeln(rows.last.summary(done, last!, journalFile(root)));
    }
    if (done != attempts) stderr.writeln('ended after $done of $attempts');
  } finally {
    root.deleteSync(recursive: true);
  }
}

File journalFile(Directory root) => File('${root.path}/demo/journal.jsonl');

class _Bucket {
  final decisions = <Duration>[];
  final scheduling = <Duration>[];
  final allocation = <Duration>[];
  final folds = <Duration>[];
  final commits = <Duration>[];
  final candidates = <int>[];
  final opens = <Duration>[];

  String summary(int done, PracticeSession session, File journal) {
    final history = attemptHistoryOfRecords(session.journal.records);
    final waiting = AllocationHistory.of(
      session.journal,
      session.acquisitionJournal,
    ).counters.asMap.length;
    return [
      done,
      _ms(_percentile(scheduling, 0.5)),
      _ms(_percentile(scheduling, 0.95)),
      _ms(_percentile(allocation, 0.5)),
      _ms(_percentile(allocation, 0.95)),
      _ms(_percentile(folds, 0.5)),
      _ms(_percentile(folds, 0.95)),
      _ms(_percentile(decisions, 0.5)),
      _ms(_percentile(decisions, 0.95)),
      commits.isEmpty ? '' : _ms(_percentile(commits, 0.5)),
      commits.isEmpty ? '' : _ms(_percentile(commits, 0.95)),
      (candidates.reduce((a, b) => a + b) / candidates.length).round(),
      session.state.materialExecution.length,
      history.startedExercises.length,
      session.journal.length,
      session.acquisitionJournal.attempts.length,
      waiting,
      journal.existsSync() ? journal.lengthSync() ~/ 1024 : 0,
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

/// Decides in process, timing the whole host call, so what follows the slot
/// can be told from evaluating it.
class _TimedHost extends InProcessScheduler {
  Duration last = Duration.zero;

  _TimedHost(super.pipeline);

  @override
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    Map<String, Set<HandConfiguration>> liveSupportHands = const {},
    List<String> uncoveredTargetIds = const [],
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    AttemptHistory? history,
    AllocationRequest? allocation,
  }) async {
    final watch = Stopwatch()..start();
    final verdict = await super.decide(
      epoch: epoch,
      state: state,
      session: session,
      dueRequirementIds: dueRequirementIds,
      liveSupportHands: liveSupportHands,
      uncoveredTargetIds: uncoveredTargetIds,
      at: at,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      history: history,
      allocation: allocation,
    );
    last = watch.elapsed;
    return verdict;
  }
}
