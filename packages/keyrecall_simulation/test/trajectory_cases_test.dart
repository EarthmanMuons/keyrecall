import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test('worst cases are limited independently per archetype', () {
    TrajectoryCase selected(String player, int seed, double magnitude) =>
        TrajectoryCase(
          trajectory: Trajectory(playerId: player, seed: seed, slots: const []),
          anomaly: Anomaly(
            detector: 'test',
            severity: AnomalySeverity.observation,
            summary: 'test',
            magnitude: magnitude,
          ),
        );

    final cases = selectTrajectoryCases(
      [
        selected('a', 0, 1),
        selected('a', 1, 3),
        selected('b', 0, 2),
        selected('b', 1, 4),
      ],
      limit: 1,
      order: CaseOrder.worst,
    );

    expect(cases.map((item) => item.trajectory.seed), [1, 1]);
    expect(cases.map((item) => item.anomaly.magnitude), [3, 4]);
  });

  test('entry cases explain the band and policy tempo', () {
    final slots = [
      _slot(
        0,
        winner: _trace(
          _exercise(tonic: 'C', tempoBpm: 126),
          bypass: ChallengeBypass.newMaterial,
        ),
        transferableBefore: 126,
      ),
      _slot(
        1,
        winner: _trace(
          _exercise(tonic: 'Db', tempoBpm: 120),
          bypass: ChallengeBypass.newMaterial,
        ),
        transferableBefore: 126,
      ),
    ];
    final trajectory = Trajectory(playerId: 'test', seed: 7, slots: slots);
    final anomaly = detectAnomalies(
      trajectory,
      requestedSlots: slots.length,
    ).singleWhere((item) => item.detector == 'entry_tempo_band_step_down');
    expect(
      detectAnomalies(
        trajectory,
      ).where((item) => item.detector == 'entry_tempo_regression'),
      isEmpty,
    );

    final rendered = renderTrajectoryCase(
      TrajectoryCase(trajectory: trajectory, anomaly: anomaly),
    );

    expect(rendered, contains('later admission band'));
    expect(rendered, contains('ADVANCED_KEYBOARD'));
    expect(rendered, contains('policy=120'));
  });

  test('hands-together cases show the guard and every later slot', () {
    const tracked = 'D_MAJOR';
    final slots = [
      for (var i = 0; i < 16; i++)
        _slot(
          i,
          handsTogether: HandsTogetherStages(
            prerequisiteSatisfied: const {tracked},
            eligible: const {tracked},
            admitted: const {tracked},
            selectable: i == 0 ? const {} : const {tracked},
            diagnostics: const {
              tracked: HandsTogetherDiagnostic(
                evaluated: 4,
                fullyEligible: 0,
                withinChallengeBand: 0,
                admitted: 1,
                selectable: 1,
                coordinationTransitions: 2,
                advancing: 1,
                fullyEligibleAdvancing: 0,
                hasFactualRetrieval: false,
                minimumOverallP: 0.2,
                maximumOverallP: 0.4,
                eligibilityCodes: {'BAND_EXECUTION_FLOOR'},
                bypasses: {'guidance_probe'},
              ),
            },
          ),
        ),
    ];
    final trajectory = Trajectory(playerId: 'test', seed: 3, slots: slots);
    final anomaly = detectAnomalies(
      trajectory,
      requestedSlots: slots.length,
    ).singleWhere((item) => item.detector == 'hands_together_stall');
    expect(anomaly.magnitude, 15);

    final rendered = renderTrajectoryCase(
      TrajectoryCase(trajectory: trajectory, anomaly: anomaly),
    );

    expect(rendered, contains('guarded=true'));
    expect(rendered, contains('C=true'));
    expect(rendered, contains('retrieved=false'));
    expect(rendered, contains('elig=BAND_EXECUTION_FLOOR'));
    expect(rendered, contains('15 P=true'));
  });
}

TrajectorySlot _slot(
  int index, {
  CandidateTrace? winner,
  double transferableBefore = 0,
  HandsTogetherStages? handsTogether,
}) {
  final selected = winner ?? _trace(_exercise());
  return TrajectorySlot(
    index: index,
    at: DateTime.utc(2026).add(Duration(minutes: index)),
    chosen: selected.exercise,
    winner: selected,
    alternatives: const [],
    performedTempoBpm: selected.exercise.conditions.tempoBpm,
    outcome: _outcome(),
    frontierBefore: const {},
    frontierAfter: const {},
    pacedBefore: 0,
    transferableBefore: transferableBefore,
    candidates: const CandidateStageCounts(
      generated: 1,
      evaluated: 1,
      eligible: 1,
      admitted: 1,
      selectable: 1,
    ),
    handsTogether:
        handsTogether ??
        const HandsTogetherStages(
          prerequisiteSatisfied: {},
          eligible: {},
          admitted: {},
          selectable: {},
        ),
  );
}

CandidateTrace _trace(Exercise exercise, {ChallengeBypass? bypass}) {
  const rank = RankKey(
    tier: EligibilityTier.fullyEligible,
    retention: 0,
    information: 0,
    diversity: 0,
    goals: 0,
  );
  return CandidateTrace(
    exercise: exercise,
    eligibility: const EligibilityDecision(
      EligibilityTier.fullyEligible,
      'eligible',
    ),
    safety: const SafetyDecision(true, 'safe'),
    challengeStatus: StageStatus.reached,
    prediction: const Prediction(
      independentRetrievalP: 0.8,
      materialAvailableP: 0.8,
      executionP: 0.8,
      topologyP: 0.8,
    ),
    isWithinChallengeBand: true,
    challengeBypass: bypass,
    challengeSurvived: true,
    priorityStatus: StageStatus.reached,
    terms: rank,
    rankKey: rank,
  );
}

Exercise _exercise({String tonic = 'C', double tempoBpm = 60}) =>
    Exercise.linear(
      material: TechnicalMaterial(tonic, ScaleForm.major),
      hands: HandConfiguration.right,
      tempoBpm: tempoBpm,
      guidance: GuidanceContext.notesPreviewedOnly,
    );

Outcome _outcome() => Outcome(
  started: true,
  retrieval: FactualRetrieval.succeeded,
  completed: true,
  materialRetrieval: 1,
  pitchIntegrity: 1,
  continuity: 1,
  temporalStability: 1,
  achievedTempoRatio: 1,
  topologyAccuracy: 1,
);
