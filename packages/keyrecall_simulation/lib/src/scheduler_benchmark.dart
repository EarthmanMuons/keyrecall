import 'dart:async';
import 'dart:isolate';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'arpeggio_policy_experiment.dart';
import 'player_archetypes.dart';
import 'python_compatible_random.dart';
import 'synthetic_player.dart';

/// One measured scheduling decision.
class BenchmarkDecision {
  final int slot;

  /// The scheduler pipeline alone.
  final Duration decide;

  /// Everything a slot does: propagation, requirement evaluation, candidate
  /// assembly, the decision, and persisting it.
  final Duration wall;

  final int generated;
  final int evaluated;
  final int ranked;

  const BenchmarkDecision({
    required this.slot,
    required this.decide,
    required this.wall,
    required this.generated,
    required this.evaluated,
    required this.ranked,
  });
}

/// What one benchmark case measured.
class SchedulerBenchmarkRun {
  final String caseName;
  final int catalogMaterials;
  final List<BenchmarkDecision> decisions;

  const SchedulerBenchmarkRun({
    required this.caseName,
    required this.catalogMaterials,
    required this.decisions,
  });

  Duration get medianDecide => _quantile(_sorted(_decide), 0.5);
  Duration get p95Decide => _quantile(_sorted(_decide), 0.95);
  Duration get maxDecide => _quantile(_sorted(_decide), 1);
  Duration get medianWall => _quantile(_sorted(_wall), 0.5);
  Duration get p95Wall => _quantile(_sorted(_wall), 0.95);
  Duration get maxWall => _quantile(_sorted(_wall), 1);

  int get generated => decisions.isEmpty ? 0 : decisions.last.generated;
  int get evaluated => decisions.isEmpty ? 0 : decisions.last.evaluated;
  int get ranked => decisions.isEmpty ? 0 : decisions.last.ranked;

  Iterable<int> get _decide =>
      decisions.map((decision) => decision.decide.inMicroseconds);
  Iterable<int> get _wall =>
      decisions.map((decision) => decision.wall.inMicroseconds);

  static List<int> _sorted(Iterable<int> values) => values.toList()..sort();

  static Duration _quantile(List<int> sorted, double probability) =>
      sorted.isEmpty
      ? Duration.zero
      : Duration(
          microseconds: sorted[((sorted.length - 1) * probability).round()],
        );
}

/// A benchmark session warmed to a chosen state, stepped one decision at a
/// time.
///
/// Stepping is separate from measuring a run because the interesting question
/// on a device is what one decision does to a frame, and that has to be driven
/// from a frame callback rather than from a loop.
class BenchmarkSession {
  final PracticeSession session;
  final int catalogMaterials;
  final DateTime _at0;
  final _TimedPipeline _pipeline;
  final PlayerState _playing;
  final PythonCompatibleRandom _random;
  int _slot;

  BenchmarkSession._({
    required this.session,
    required this.catalogMaterials,
    required DateTime at0,
    required _TimedPipeline pipeline,
    required PlayerState playing,
    required PythonCompatibleRandom random,
    required int slot,
  }) : _at0 = at0,
       _pipeline = pipeline,
       _playing = playing,
       _random = random,
       _slot = slot;

  /// The learner state the next decision reads.
  LearnerState get learnerState => session.state;

  /// The sitting the next decision reads.
  SessionState get sessionState => session.session;

  /// When the next decision happens.
  DateTime get nextAt => _at0.add(Duration(minutes: _slot + 1));

  /// Decides one slot, plays it, and reports what the decision cost.
  ///
  /// Null once the scope stops presenting work, which ends a run rather than
  /// failing it.
  Future<BenchmarkDecision?> step() async {
    final slot = _slot++;
    final at = _at0.add(Duration(minutes: slot + 1));
    final wall = Stopwatch()..start();
    final decision = await session.decideOutcome(at: at);
    wall.stop();
    if (decision case PresentedAttempt(:final exercise)) {
      await session.closeWithOutcome(
        _playing.play(exercise, _random),
        observedWallTime: at,
      );
      return BenchmarkDecision(
        slot: slot,
        decide: _pipeline.lastDecide,
        wall: wall.elapsed,
        generated: _pipeline.lastGenerated,
        evaluated: _pipeline.lastEvaluated,
        ranked: _pipeline.lastRanked,
      );
    }
    return null;
  }
}

/// Opens a session on [scope] and warms it through [warmupSlots].
///
/// Warm-up matters twice: it is how a learner reaches the state whose decisions
/// are expensive, and on a release build it is also how the code under
/// measurement gets warm.
Future<BenchmarkSession> openBenchmarkSession({
  required ArpeggioPolicyScope scope,
  required SyntheticPlayer player,
  required int warmupSlots,
  int seed = 0,
  void Function(int completed, int total)? onProgress,
}) async {
  final at0 = DateTime.utc(2026);
  final learner = LearnerModel(params: v1PrototypeLearnerParams);
  final pipeline = _TimedPipeline(learner: learner);
  final fixture = arpeggioPolicyFixture(scope);
  final session = await PracticeSession.open(
    store: InMemoryPracticeStore(createdAt: at0),
    profile: Profile(
      id: 'benchmark-${scope.name}-${player.id}',
      displayName: player.id,
      createdAt: at0,
      placement: player.placement,
    ),
    materials: fixture.materials,
    learner: learner,
    pipeline: pipeline,
    goal: fixture.goal,
    scopeResolver: PracticeScopeResolver(
      families: const [
        ScalePracticeMaterialFamily(),
        ArpeggioPracticeMaterialFamily(),
      ],
    ),
    sessionId: 'benchmark-${scope.name}-${player.id}',
  );
  final benchmark = BenchmarkSession._(
    session: session,
    catalogMaterials: fixture.materials.length,
    at0: at0,
    pipeline: pipeline,
    playing: player.begin(),
    random: PythonCompatibleRandom(seed),
    slot: 0,
  );
  for (var slot = 0; slot < warmupSlots; slot++) {
    if (await benchmark.step() == null) break;
    onProgress?.call(slot + 1, warmupSlots);
  }
  return benchmark;
}

/// Drives one archetype through [warmupSlots] and measures [measuredSlots].
Future<SchedulerBenchmarkRun> runSchedulerBenchmark({
  required String caseName,
  required ArpeggioPolicyScope scope,
  required SyntheticPlayer player,
  required int warmupSlots,
  required int measuredSlots,
  int seed = 0,
  void Function(int completed, int total)? onProgress,
}) async {
  final benchmark = await openBenchmarkSession(
    scope: scope,
    player: player,
    warmupSlots: warmupSlots,
    seed: seed,
    onProgress: (completed, total) =>
        onProgress?.call(completed, warmupSlots + measuredSlots),
  );
  final decisions = <BenchmarkDecision>[];
  for (var measured = 0; measured < measuredSlots; measured++) {
    final decision = await benchmark.step();
    if (decision == null) break;
    decisions.add(decision);
    onProgress?.call(warmupSlots + measured + 1, warmupSlots + measuredSlots);
  }

  return SchedulerBenchmarkRun(
    caseName: caseName,
    catalogMaterials: benchmark.catalogMaterials,
    decisions: decisions,
  );
}

/// Runs the benchmark on a worker isolate and returns its decision costs.
///
/// Top level, and deliberately: a closure written inside a widget's method
/// captures that method's context, so `Isolate.run` is handed the whole element
/// tree and refuses to send it. Here the closure can reach nothing but these
/// parameters, all of which are primitives.
Future<List<int>> runSchedulerBenchmarkOnWorker({
  required String scopeName,
  required String playerId,
  required int warmupSlots,
  required int measuredSlots,
  int seed = 0,
}) => Isolate.run(
  () => runSchedulerBenchmarkMicroseconds(
    scopeName: scopeName,
    playerId: playerId,
    warmupSlots: warmupSlots,
    measuredSlots: measuredSlots,
    seed: seed,
  ),
);

/// The benchmark behind a boundary only primitives cross.
///
/// What a worker isolate can be handed: an archetype and a scope by name, and
/// counts. The run itself constructs everything else on the far side.
Future<List<int>> runSchedulerBenchmarkMicroseconds({
  required String scopeName,
  required String playerId,
  required int warmupSlots,
  required int measuredSlots,
  int seed = 0,
}) async {
  final run = await runSchedulerBenchmark(
    caseName: playerId,
    scope: ArpeggioPolicyScope.values.byName(scopeName),
    player: PlayerArchetypes.all.firstWhere(
      (archetype) => archetype.id == playerId,
    ),
    warmupSlots: warmupSlots,
    measuredSlots: measuredSlots,
    seed: seed,
  );
  return [for (final decision in run.decisions) decision.decide.inMicroseconds];
}

class _TimedPipeline extends SchedulerPipeline {
  final Stopwatch _watch = Stopwatch();
  Duration lastDecide = Duration.zero;
  int lastGenerated = 0;
  int lastEvaluated = 0;
  int lastRanked = 0;

  _TimedPipeline({required super.learner});

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
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    lastGenerated = candidates.length;
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
      practiceEntryPolicy: practiceEntryPolicy,
    );
    _watch.stop();
    lastDecide = _watch.elapsed;
    lastEvaluated = slot.result.traces.length;
    lastRanked = slot.result.traces.where((trace) => trace.isRanked).length;
    return slot;
  }
}

/// A worker isolate that owns a scope and answers one decision at a time.
///
/// The production message shape, as far as a benchmark can stand in for it:
/// the state a slot decides from goes across and the chosen exercise comes
/// back. The candidate envelope never moves, because the worker resolves it
/// once from the catalog the same way the session does.
class SchedulerWorker {
  final SendPort _requests;
  final ReceivePort _responses;
  final StreamIterator<Object?> _incoming;

  SchedulerWorker._(this._requests, this._responses, this._incoming);

  /// Spawns a worker holding [scopeName]'s resolved scope.
  static Future<SchedulerWorker> start(String scopeName) async {
    final responses = ReceivePort();
    final incoming = StreamIterator<Object?>(responses);
    await Isolate.spawn(_serve, (responses.sendPort, scopeName));
    await incoming.moveNext();
    return SchedulerWorker._(
      incoming.current! as SendPort,
      responses,
      incoming,
    );
  }

  /// The exercise the scheduler would present, or null where it is blocked.
  Future<Exercise?> decide({
    required LearnerState state,
    required SessionState session,
    required DateTime at,
  }) async {
    _requests.send((state, session, at));
    await _incoming.moveNext();
    return _incoming.current as Exercise?;
  }

  void stop() {
    _requests.send(null);
    _responses.close();
  }

  static Future<void> _serve((SendPort, String) start) async {
    final (replies, scopeName) = start;
    final scope = ArpeggioPolicyScope.values.byName(scopeName);
    final fixture = arpeggioPolicyFixture(scope);
    final resolution =
        PracticeScopeResolver(
              families: const [
                ScalePracticeMaterialFamily(),
                ArpeggioPracticeMaterialFamily(),
              ],
            ).resolve(
              goal: fixture.goal,
              focus: PracticeFocus.unrestricted,
              catalog: fixture.materials,
              instrument: InstrumentProfile(),
            )
            as ValidPracticeScope;
    final candidates = distinctCandidatesOf(resolution.scope.requirements);
    final pipeline = SchedulerPipeline(
      learner: const LearnerModel(params: v1PrototypeLearnerParams),
    );

    final requests = ReceivePort();
    replies.send(requests.sendPort);
    await for (final request in requests) {
      if (request == null) break;
      final (state, session, at) =
          request as (LearnerState, SessionState, DateTime);
      final selection = pipeline.decide(
        state: state,
        session: session,
        candidates: candidates,
        at: at,
        practiceEntryPolicy: resolution.entryPolicy,
      );
      replies.send(switch (selection) {
        CandidateSelected(:final candidate) => candidate.exercise,
        SelectionBlocked() => null,
      });
    }
    requests.close();
  }
}
