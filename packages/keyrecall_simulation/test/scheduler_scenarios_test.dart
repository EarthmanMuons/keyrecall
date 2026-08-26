import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Longitudinal behavioral scenarios: does the scheduler behave well over
/// repeated decide, play, update, decide cycles?
///
/// A different question from the information-boundary invariants in
/// keyrecall_scheduler, which ask whether a forbidden input can move a stage's
/// decision. Each scenario here corresponds to a failure mode the synthetic
/// analysis actually found, and to the mechanism that resolved it. The
/// repetition guard's own two properties are unit-tested directly in
/// keyrecall_scheduler; what appears here is whether it holds up over a run.
void main() {
  const learner = LearnerModel();
  const pipeline = SchedulerPipeline(learner: learner);
  const config = v1SchedulerConfig;
  const learnerParams = v1PrototypeLearnerParams;
  final instrument = InstrumentProfile();

  SchedulerAgent agentOver(List<TechnicalMaterial> materials) => SchedulerAgent(
    pipeline: pipeline,
    instrument: instrument,
    materials: materials,
  );

  int independence(Exercise exercise) => exercise.guidance.independence;

  test('guidance fades instead of sticking at maximum support', () {
    // A cued attempt never tests retrieval, so once the scheduler shifted to
    // full cueing it could never re-anchor the memory clock and stayed there.
    // The guidance probe is what offers a less supported variant once enough
    // time has passed since the last confirmed retrieval.
    final simulation = PracticeSimulation.of(
      SyntheticProfile.techniqueStrongMemoryWeak,
      seed: 0,
    );
    final agent = agentOver([v1ScaleCatalog.first]);

    runSessions(simulation, agent, sessionCount: 3, attemptsPerSession: 20);

    final levels = agent.selections
        .map((trace) => independence(trace.exercise))
        .toList();
    expect(levels.length, greaterThanOrEqualTo(10));

    const tailWindow = 10;
    final tail = levels.sublist(levels.length - tailWindow);
    final earlier = levels.sublist(0, levels.length - tailWindow);
    final stuck =
        tail.every((level) => level == 0) && earlier.any((level) => level > 0);
    expect(
      stuck,
      isFalse,
      reason: 'guidance became permanently stuck at maximum support',
    );
  });

  test('one material is not repeated indefinitely', () {
    // The same guidance and memory trap in another form: unbounded retention
    // need entrenched whichever material could never resolve it.
    final simulation = PracticeSimulation.of(
      SyntheticProfile.advanced,
      seed: 1,
    );
    final agent = agentOver(v1ScaleCatalog.take(3).toList());

    runSessions(simulation, agent, sessionCount: 4, attemptsPerSession: 20);

    final selected = agent.selections
        .map((trace) => trace.exercise.material.materialId)
        .toList();
    var longestRun = 1;
    var currentRun = 1;
    for (var i = 1; i < selected.length; i++) {
      currentRun = selected[i] == selected[i - 1] ? currentRun + 1 : 1;
      longestRun = math.max(longestRun, currentRun);
    }

    expect(longestRun, lessThanOrEqualTo(config.diversity.recentWindow));
  });

  test('old material resurfaces once its retention need rises', () {
    final materialA = v1ScaleCatalog[0];
    final materialB = v1ScaleCatalog[1];
    final simulation = PracticeSimulation.of(
      SyntheticProfile.advanced,
      seed: 2,
    );

    final onlyA = agentOver([materialA]);
    simulation.run(20, chooser: onlyA.choose, onOutcome: onlyA.observe);

    final onlyB = agentOver([materialB]);
    simulation.run(15, chooser: onlyB.choose, onOutcome: onlyB.observe);

    final both = agentOver([materialA, materialB]);
    simulation.run(20, chooser: both.choose, onOutcome: both.observe);

    expect(
      both.selections.map((trace) => trace.exercise.material.materialId),
      contains(materialA.materialId),
      reason: 'material A never came back after going unpracticed',
    );
  });

  test('new-material introduction is sensitive to the learner', () {
    // The introduction envelope gates on the same predicted success every
    // profile already produces, so which realizations clear it varies by
    // learner rather than being fixed for everyone.
    Exercise firstChoice(PlacementTier tier) {
      final agent = agentOver(v1ScaleCatalog);
      return agent.choose(
        AttemptContext(
          rng: PythonCompatibleRandom(0),
          attemptIndex: 0,
          state: learner.placementState(tier, at: defaultSimulationEpoch),
          at: defaultSimulationEpoch,
        ),
      );
    }

    expect(
      firstChoice(PlacementTier.beginner),
      isNot(firstChoice(PlacementTier.advanced)),
    );
  });

  test('eligibility progresses as both hands improve', () {
    // Starts an advanced-truth learner from an artificially low belief:
    // practice can genuinely converge toward the true ability, whereas a true
    // beginner's ability sits permanently below the threshold and no amount of
    // practice could cross it.
    final truth = SyntheticProfile.advanced.build(
      start: defaultSimulationEpoch,
    );
    final state = learner.placementState(
      truth.selfReportTier,
      at: defaultSimulationEpoch,
    );
    state.competency(Competency.rhScaleExecution).mean = -0.3;
    state.competency(Competency.lhScaleExecution).mean = -0.3;

    final material = v1ScaleCatalog.first;
    final handsTogether = Exercise.linear(
      material: material,
      hands: HandConfiguration.together,
    );
    expect(
      pipeline.eligibilityFor(state, handsTogether).tier,
      EligibilityTier.provisionallyEligible,
    );

    final simulation = PracticeSimulation.from(
      truth: truth,
      state: state,
      seed: 5,
    );
    simulation.run(
      300,
      chooser: (context) => Exercise.linear(
        material: material,
        hands: context.rng.choice(const [
          HandConfiguration.right,
          HandConfiguration.left,
        ]),
      ),
    );

    final after = pipeline.eligibilityFor(state, handsTogether);
    expect(after.tier, EligibilityTier.fullyEligible, reason: after.reason);
  });

  test('a recovery context is temporary', () {
    final simulation = PracticeSimulation.of(
      SyntheticProfile.techniqueStrongMemoryWeak,
      seed: 6,
    );
    final agent = agentOver([v1ScaleCatalog.first]);

    simulation.run(30, chooser: agent.choose, onOutcome: agent.observe);

    var sawRecoveryAfterFailure = false;
    var sawNoRecoveryAfterSuccess = false;
    for (var i = 1; i < agent.records.length; i++) {
      final record = agent.records[i];
      final previous = agent.records[i - 1];
      final selected = record.selected;
      final priorOutcome = previous.outcome;
      if (selected == null || priorOutcome == null) continue;

      final usedRecovery = selected.challengeBypass == ChallengeBypass.recovery;
      if (priorOutcome.retrieval == FactualRetrieval.failed) {
        sawRecoveryAfterFailure = sawRecoveryAfterFailure || usedRecovery;
      } else {
        expect(
          usedRecovery,
          isFalse,
          reason:
              'attempt $i recovered even though the prior retrieval was '
              '${priorOutcome.retrieval.name}',
        );
        sawNoRecoveryAfterSuccess = true;
      }
    }

    expect(sawRecoveryAfterFailure, isTrue);
    expect(sawNoRecoveryAfterSuccess, isTrue);
  });

  test('a failed guidance probe steps toward more support, not less', () {
    // A failed probe opens a recovery context, and recovery is checked before
    // the probes. Because the retention term rewards higher retrieval demand,
    // nothing in ranking would otherwise favor restoring support, and both
    // traced probe failures jumped straight to fully unguided.
    final material = v1ScaleCatalog.first;
    final state = learner.placementState(
      PlacementTier.advanced,
      at: defaultSimulationEpoch,
    );
    final at = defaultSimulationEpoch;
    final longAgo = at.plusDays(-20);
    state.materialMemoryFor(material.materialId, learnerParams)
      ..memoryAnchorAt = longAgo
      ..factualLastRetrievalAt = longAgo
      ..lastRetrievalAttemptAt = longAgo
      ..establishedIndependence =
          GuidanceContext.notesPreviewedOnly.independence
      ..logCurrentHalfLife = math.log(0.1)
      ..logConsolidatedHalfLife = math.log(0.1);

    final candidates = generateCandidates(instrument, [material]);
    final probes = pipeline
        .evaluate(
          state: state,
          session: SessionState(),
          candidates: candidates,
          at: at,
        )
        .where(
          (trace) => trace.challengeBypass == ChallengeBypass.guidanceProbe,
        )
        .toList();
    expect(probes, isNotEmpty);

    final failedProbe = probes.first.exercise;
    final survivors = pipeline
        .evaluate(
          state: state,
          session: SessionState(lastFailedExercise: failedProbe),
          candidates: candidates,
          at: at.plusDays(0.5),
        )
        .where((trace) => trace.challengeSurvived)
        .toList();

    expect(survivors, hasLength(1));
    expect(survivors.single.challengeBypass, ChallengeBypass.recovery);
    expect(
      independence(survivors.single.exercise),
      lessThan(independence(failedProbe)),
    );
  });

  test('recovery preserves the motor challenge', () {
    // Before recovery targeted the exact failed exercise, it admitted every
    // execution combination, and the winner collapsed to the easiest
    // realization overall rather than a guidance-adjusted sibling.
    final material = v1ScaleCatalog.first;
    final state = learner.placementState(
      PlacementTier.advanced,
      at: defaultSimulationEpoch,
    )..materialMemoryFor(material.materialId, learnerParams);

    final justAttempted = Exercise.linear(
      material: material,
      hands: HandConfiguration.right,
      octaves: 2,
      tempoBpm: 100,
    );
    final session = SessionState(
      lastFailedExercise: justAttempted,
      recentMaterialIds: [material.materialId],
    );

    final at = defaultSimulationEpoch.plusDays(0.5);
    final traces = pipeline.evaluate(
      state: state,
      session: session,
      candidates: generateCandidates(instrument, [material]),
      at: at,
    );
    final winner = pipeline.selectChoice(traces, session);

    expect(winner, isNotNull);
    expect(winner!.exercise, recoveryTarget(justAttempted));
    expect(winner.exercise.conditions, justAttempted.conditions);
  });

  test('material that has never succeeded is not permanently trapped', () {
    // Recovery can escalate a material to maximum cueing after two failures,
    // before any success anchors the clock, and the guidance probe cannot fire
    // without that anchor. The bootstrap probe is what keeps offering a
    // retrieval-observing candidate.
    //
    // Not a claim that those probes eventually succeed, which is stochastic.
    // Only that the scheduler keeps offering one.
    final simulation = PracticeSimulation.of(
      SyntheticProfile.techniqueStrongMemoryWeak,
      seed: 2,
    );
    final agent = agentOver([v1ScaleCatalog.first]);

    runSessions(simulation, agent, sessionCount: 4, attemptsPerSession: 20);

    final levels = agent.selections
        .map((trace) => independence(trace.exercise))
        .toList();
    expect(levels.length, greaterThanOrEqualTo(40));

    var longestCuedRun = 0;
    var currentRun = 0;
    for (final level in levels) {
      currentRun = level == 0 ? currentRun + 1 : 0;
      longestCuedRun = math.max(longestCuedRun, currentRun);
    }

    // Comfortably above one probe interval's worth of attempts, so a
    // legitimate wait does not trip this, but a permanent trap does.
    expect(longestCuedRun, lessThanOrEqualTo(25));
  });

  test('a decision that admits nothing is reported, not papered over', () {
    final simulation = PracticeSimulation.of(
      SyntheticProfile.advanced,
      seed: 0,
    );
    final agent = agentOver([v1ScaleCatalog.first]);
    agent.session.attemptsThisSession = config.safety.maxSessionAttempts;

    expect(
      () => simulation.run(1, chooser: agent.choose, onOutcome: agent.observe),
      throwsA(isA<NoAdmittedCandidate>()),
    );
    expect(agent.records.single.selected, isNull);
  });
}
