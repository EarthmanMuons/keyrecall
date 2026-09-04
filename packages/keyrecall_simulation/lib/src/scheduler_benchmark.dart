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

/// Drives one archetype through [warmupSlots] and measures [measuredSlots].
///
/// The real session, scope evaluator, learner model, and scheduler, over the
/// same catalogs the decision-cost census uses. Warm-up matters twice here:
/// it is how a learner reaches the state whose decisions are expensive, and on
/// a release build it is also how the code under measurement gets warm.
Future<SchedulerBenchmarkRun> runSchedulerBenchmark({
  required String caseName,
  required ArpeggioPolicyScope scope,
  required SyntheticPlayer player,
  required int warmupSlots,
  required int measuredSlots,
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
  final playing = player.begin();
  final random = PythonCompatibleRandom(seed);
  final decisions = <BenchmarkDecision>[];
  final total = warmupSlots + measuredSlots;

  for (var slot = 0; slot < total; slot++) {
    final at = at0.add(Duration(minutes: slot + 1));
    final wall = Stopwatch()..start();
    final decision = await session.decideOutcome(at: at);
    wall.stop();
    if (slot >= warmupSlots) {
      decisions.add(
        BenchmarkDecision(
          slot: slot,
          decide: pipeline.lastDecide,
          wall: wall.elapsed,
          generated: pipeline.lastGenerated,
          evaluated: pipeline.lastEvaluated,
          ranked: pipeline.lastRanked,
        ),
      );
    }
    onProgress?.call(slot + 1, total);
    if (decision case PresentedAttempt(:final exercise)) {
      await session.closeWithOutcome(
        playing.play(exercise, random),
        observedWallTime: at,
      );
    } else {
      break;
    }
  }

  return SchedulerBenchmarkRun(
    caseName: caseName,
    catalogMaterials: fixture.materials.length,
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
  SelectionResult decide({
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
    final result = super.decide(
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
    lastEvaluated = result.traces.length;
    lastRanked = result.traces.where((trace) => trace.isRanked).length;
    return result;
  }
}
