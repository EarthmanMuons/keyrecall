import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'arpeggio_policy_experiment.dart';
import 'python_compatible_random.dart';
import 'synthetic_player.dart';

/// What one scheduling decision cost, and how much work reached each stage.
class DecisionCostSample {
  final ArpeggioPolicyScope scope;
  final String playerId;
  final int slot;
  final int catalogMaterials;
  final int generated;
  final int evaluated;
  final int distinctMaterials;
  final int distinctRealizations;
  final int fullyEligible;
  final int provisional;
  final int challengeReached;
  final int challengeSurvived;
  final int ranked;
  final int informationKeys;
  final int guarded;
  final int afterIntroductionCap;
  final int selectable;
  final Duration requirements;
  final Duration assemble;
  final Duration evaluate;
  final Duration guard;
  final Duration cap;
  final Duration pace;
  final Duration decide;
  final Duration slotTotal;

  const DecisionCostSample({
    required this.scope,
    required this.playerId,
    required this.slot,
    required this.catalogMaterials,
    required this.generated,
    required this.evaluated,
    required this.distinctMaterials,
    required this.distinctRealizations,
    required this.fullyEligible,
    required this.provisional,
    required this.challengeReached,
    required this.challengeSurvived,
    required this.ranked,
    required this.informationKeys,
    required this.guarded,
    required this.afterIntroductionCap,
    required this.selectable,
    required this.requirements,
    required this.assemble,
    required this.evaluate,
    required this.guard,
    required this.cap,
    required this.pace,
    required this.decide,
    required this.slotTotal,
  });

  /// How much of the generated set survives to ranking.
  double get rankedShare => generated == 0 ? 0 : ranked / generated;

  /// How much of the generated set is a distinct execution realization.
  ///
  /// Guidance variants share every expensive prediction channel, so the
  /// reciprocal is how many candidates one realization's work is spread over.
  double get realizationShare =>
      generated == 0 ? 0 : distinctRealizations / generated;

  double get microsecondsPerCandidate =>
      generated == 0 ? 0 : decide.inMicroseconds / generated;

  double get microsecondsPerMaterial =>
      catalogMaterials == 0 ? 0 : decide.inMicroseconds / catalogMaterials;
}

/// Profiles one trajectory, sampling the decisions at [slots].
Future<List<DecisionCostSample>> runDecisionCostTrajectory({
  required ArpeggioPolicyScope scope,
  required SyntheticPlayer player,
  required Set<int> slots,
  int seed = 0,
}) async {
  final at0 = DateTime.utc(2026);
  final horizon = slots.reduce((a, b) => a > b ? a : b);
  final learner = LearnerModel(params: v1PrototypeLearnerParams);
  final pipeline = _ProfilingPipeline(learner: learner);
  final fixture = arpeggioPolicyFixture(scope);
  final session = await PracticeSession.open(
    store: InMemoryPracticeStore(createdAt: at0),
    profile: Profile(
      id: 'cost-${scope.name}-${player.id}',
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
    sessionId: 'cost-${scope.name}-${player.id}',
  );
  final playing = player.begin();
  final random = PythonCompatibleRandom(seed);
  final samples = <DecisionCostSample>[];
  final phases = _PhaseTimer(scope: scope, fixture: fixture, learner: learner);

  for (var slot = 0; slot <= horizon; slot++) {
    final at = at0.add(Duration(minutes: slot + 1));
    pipeline.reset();
    final phase = slots.contains(slot) ? phases.measure(session, at) : null;
    final wall = Stopwatch()..start();
    final decision = await session.decideOutcome(at: at);
    wall.stop();
    if (phase != null) {
      samples.add(
        pipeline.sample(
          scope: scope,
          playerId: player.id,
          slot: slot,
          catalogMaterials: fixture.materials.length,
          requirements: phase.requirements,
          assemble: phase.assemble,
          slotTotal: wall.elapsed,
        ),
      );
    }
    if (decision case PresentedAttempt(:final exercise)) {
      await session.closeWithOutcome(
        playing.play(exercise, random),
        observedWallTime: at,
      );
    } else {
      break;
    }
  }
  return samples;
}

/// Every catalog, archetype, and trajectory position of the cost matrix.
Future<List<DecisionCostSample>> runDecisionCostMatrix({
  required Iterable<ArpeggioPolicyScope> scopes,
  required Iterable<SyntheticPlayer> players,
  required Set<int> slots,
  int seed = 0,
  void Function(int completed, int total)? onProgress,
}) async {
  final samples = <DecisionCostSample>[];
  var completed = 0;
  final total = scopes.length * players.length;
  for (final scope in scopes) {
    for (final player in players) {
      samples.addAll(
        await runDecisionCostTrajectory(
          scope: scope,
          player: player,
          slots: slots,
          seed: seed,
        ),
      );
      onProgress?.call(++completed, total);
    }
  }
  return samples;
}

/// Times the session work that precedes the scheduler.
///
/// It repeats requirement evaluation and candidate assembly on the same inputs
/// the session is about to use, which costs a sampled slot one extra pass and
/// keeps production free of timing instrumentation.
class _PhaseTimer {
  final ResolvedPracticeScope scope;
  final LearnerModel learner;
  final PracticeScopeEvaluator evaluator = const PracticeScopeEvaluator();

  _PhaseTimer({
    required ArpeggioPolicyScope scope,
    required ({List<TechnicalMaterial> materials, PracticeGoal goal}) fixture,
    required this.learner,
  }) : scope =
           (PracticeScopeResolver(
                     families: const [
                       ScalePracticeMaterialFamily(),
                       ArpeggioPracticeMaterialFamily(),
                     ],
                   ).resolve(
                     goal: fixture.goal,
                     focus: PracticeFocus(),
                     catalog: fixture.materials,
                     instrument: InstrumentProfile(),
                   )
                   as ValidPracticeScope)
               .scope;

  ({Duration requirements, Duration assemble}) measure(
    PracticeSession session,
    DateTime at,
  ) {
    final state = session.state.copy();
    learner.propagate(state, at);
    final requirements = Stopwatch()..start();
    final evaluated = evaluator.evaluate(
      scope: scope,
      state: state,
      journal: session.journal,
      learner: learner,
      at: at,
    );
    requirements.stop();
    final due = scope.isNarrow
        ? evaluated.dueRequirements.toList()
        : evaluated.requirements;
    final assemble = Stopwatch()..start();
    final candidates = distinctCandidatesOf(
      due.map((requirement) => requirement.resolved),
    );
    assemble.stop();
    return (
      requirements: requirements.elapsed,
      assemble: candidates.isEmpty ? Duration.zero : assemble.elapsed,
    );
  }
}

/// A pipeline that times each stage and records what reached it.
class _ProfilingPipeline extends SchedulerPipeline {
  final Stopwatch _evaluate = Stopwatch();
  final Stopwatch _guard = Stopwatch();
  final Stopwatch _cap = Stopwatch();
  final Stopwatch _pace = Stopwatch();
  final Stopwatch _decide = Stopwatch();
  List<CandidateTrace> _traces = const [];
  int _generated = 0;
  int _guarded = 0;
  int _afterCap = 0;
  int _selectable = 0;

  _ProfilingPipeline({required super.learner});

  void reset() {
    for (final watch in [_evaluate, _guard, _cap, _pace, _decide]) {
      watch.reset();
    }
    _traces = const [];
    _generated = 0;
    _guarded = 0;
    _afterCap = 0;
    _selectable = 0;
  }

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
    _generated = candidates.length;
    _decide.start();
    final result = super.decide(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      practiceEntryPolicy: practiceEntryPolicy,
    );
    _decide.stop();
    return result;
  }

  @override
  List<CandidateTrace> evaluate({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    _evaluate.start();
    _traces = super.evaluate(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      practiceEntryPolicy: practiceEntryPolicy,
    );
    _evaluate.stop();
    return _traces;
  }

  @override
  List<CandidateTrace> applyRepetitionGuard(
    List<CandidateTrace> traces,
    SessionState session,
  ) {
    _guard.start();
    final guarded = super.applyRepetitionGuard(traces, session);
    _guard.stop();
    _guarded = guarded.length;
    return guarded;
  }

  @override
  IntroductionDecision capIntroductions(
    List<CandidateTrace> guarded,
    List<CandidateTrace> traces,
    LearnerState? state,
  ) {
    _cap.start();
    final decision = super.capIntroductions(guarded, traces, state);
    _cap.stop();
    _afterCap = decision.selectable.length;
    return decision;
  }

  @override
  PacingDecision pace(List<CandidateTrace> guarded, SessionState session) {
    _pace.start();
    final decision = super.pace(guarded, session);
    _pace.stop();
    _selectable = decision.selectable.length;
    return decision;
  }

  DecisionCostSample sample({
    required ArpeggioPolicyScope scope,
    required String playerId,
    required int slot,
    required int catalogMaterials,
    required Duration requirements,
    required Duration assemble,
    required Duration slotTotal,
  }) {
    final ranked = [
      for (final trace in _traces)
        if (trace.isRanked) trace,
    ];
    return DecisionCostSample(
      scope: scope,
      playerId: playerId,
      slot: slot,
      catalogMaterials: catalogMaterials,
      generated: _generated,
      evaluated: _traces.length,
      distinctMaterials: {
        for (final trace in _traces) trace.exercise.material.materialId,
      }.length,
      distinctRealizations: {
        for (final trace in _traces)
          trace.exercise.withGuidance(GuidanceContext.unguided),
      }.length,
      fullyEligible: _traces
          .where(
            (trace) => trace.eligibility.tier == EligibilityTier.fullyEligible,
          )
          .length,
      provisional: _traces
          .where(
            (trace) => trace.eligibility.tier != EligibilityTier.fullyEligible,
          )
          .length,
      challengeReached: _traces
          .where((trace) => trace.challengeStatus.isReached)
          .length,
      challengeSurvived: _traces
          .where((trace) => trace.challengeSurvived)
          .length,
      ranked: ranked.length,
      informationKeys: {
        for (final trace in ranked) informationKeyFor(trace.exercise),
      }.length,
      guarded: _guarded,
      afterIntroductionCap: _afterCap,
      selectable: _selectable,
      requirements: requirements,
      assemble: assemble,
      evaluate: _evaluate.elapsed,
      guard: _guard.elapsed,
      cap: _cap.elapsed,
      pace: _pace.elapsed,
      decide: _decide.elapsed,
      slotTotal: slotTotal,
    );
  }
}
