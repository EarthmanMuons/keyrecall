import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  group('realization detectors', () {
    test('a surpassed choice loses to an otherwise tied advance', () {
      final chosen = _trace(
        _exercise(),
        realization: RealizationRank.surpassed,
      );
      final advancing = _trace(
        _exercise(tempoBpm: 63),
        realization: RealizationRank.advancing,
      );
      final found = _find('realization_stall', [
        _slot(0, winner: chosen, alternatives: [advancing]),
      ]);

      expect(found, hasLength(1));
    });

    test('a coordination transition explains the surpassed choice', () {
      final chosen = _trace(
        _exercise(),
        realization: RealizationRank.surpassed,
        transition: true,
      );
      final advancing = _trace(
        _exercise(tempoBpm: 63),
        realization: RealizationRank.advancing,
      );

      expect(
        _find('realization_stall', [
          _slot(0, winner: chosen, alternatives: [advancing]),
        ]),
        isEmpty,
      );
    });

    test('an unmeasured choice loses to an otherwise tied nearer entry', () {
      final chosen = _trace(_exercise(), realizationFit: -2);
      final nearer = _trace(_exercise(tempoBpm: 72), realizationFit: 0);

      expect(
        _find('unmeasured_entry_ignored', [
          _slot(0, winner: chosen, alternatives: [nearer]),
        ]),
        hasLength(1),
      );
    });

    test('a coordination transition explains the unmeasured choice', () {
      final chosen = _trace(_exercise(), realizationFit: -2, transition: true);
      final nearer = _trace(_exercise(tempoBpm: 72), realizationFit: 0);

      expect(
        _find('unmeasured_entry_ignored', [
          _slot(0, winner: chosen, alternatives: [nearer]),
        ]),
        isEmpty,
      );
    });
  });

  test('a dry sitting reports the terminal slot', () {
    final terminal = TerminalTrajectorySlot(
      index: 0,
      at: _at(0),
      traces: [_trace(_exercise())],
      selectable: const [],
      candidates: const CandidateStageCounts(
        generated: 2,
        evaluated: 1,
        eligible: 0,
        admitted: 0,
        selectable: 0,
      ),
    );
    final trajectory = Trajectory(
      playerId: 'test',
      seed: 0,
      slots: const [],
      terminal: terminal,
    );

    final found = detectAnomalies(trajectory, requestedSlots: 1).single;
    expect(found.detector, 'sitting_ran_dry');
    expect(found.census, contains('slot 0'));
    expect(found.census, contains('0 selectable'));
  });

  group('entry tempo', () {
    test('early material must use the transferable pace', () {
      final slot = _slot(
        0,
        winner: _trace(
          _exercise(tempoBpm: 92),
          bypass: ChallengeBypass.newMaterial,
        ),
        transferableBefore: 96,
      );

      expect(_find('entry_tempo_ignores_pace', [slot]), hasLength(1));
    });

    test('later material may enter one rung below the pace', () {
      final slot = _slot(
        0,
        winner: _trace(
          _exercise(tonic: 'Db', tempoBpm: 92),
          bypass: ChallengeBypass.newMaterial,
        ),
        transferableBefore: 96,
      );

      expect(_find('entry_tempo_ignores_pace', [slot]), isEmpty);
    });

    test('the current failure does not explain the chosen entry tempo', () {
      final first = _slot(
        0,
        winner: _trace(
          _exercise(tempoBpm: 96),
          bypass: ChallengeBypass.newMaterial,
        ),
      );
      final second = _slot(
        1,
        winner: _trace(
          _exercise(tonic: 'G', tempoBpm: 80),
          bypass: ChallengeBypass.newMaterial,
        ),
        outcome: _outcome(completed: false),
      );

      expect(_find('entry_tempo_regression', [first, second]), hasLength(1));
    });

    test('an earlier failure resets the entry comparison', () {
      final slots = [
        _slot(
          0,
          winner: _trace(
            _exercise(tempoBpm: 96),
            bypass: ChallengeBypass.newMaterial,
          ),
        ),
        _slot(1, outcome: _outcome(completed: false)),
        _slot(
          2,
          winner: _trace(
            _exercise(tonic: 'G', tempoBpm: 80),
            bypass: ChallengeBypass.newMaterial,
          ),
        ),
      ];

      expect(_find('entry_tempo_regression', slots), isEmpty);
    });
  });

  group('progression stall', () {
    test('managed completion without a frontier change remains stalled', () {
      final slots = [
        for (var i = 0; i < 12; i++)
          _slot(i, frontierBefore: const {1: 60}, frontierAfter: const {1: 60}),
      ];

      expect(_find('progression_stall', slots), hasLength(1));
    });

    test('completion below the motor threshold is learner struggle', () {
      final slots = [
        for (var i = 0; i < 12; i++)
          _slot(
            i,
            outcome: _outcome(continuity: 0.4, temporalStability: 0.4),
            frontierBefore: const {1: 60},
            frontierAfter: const {1: 60},
          ),
      ];

      expect(_find('progression_stall', slots), isEmpty);
      expect(_find('progression_struggle', slots), hasLength(1));
    });

    test('an actual frontier change resets the stall', () {
      final slots = [
        for (var i = 0; i < 12; i++)
          _slot(
            i,
            frontierBefore: const {1: 60},
            frontierAfter: i == 6 ? const {1: 63} : const {1: 60},
          ),
      ];

      expect(_find('progression_stall', slots), isEmpty);
    });
  });

  group('hands together stall', () {
    test('tracks each ready material to its own selection', () {
      final slots = [
        for (var i = 0; i < 17; i++)
          _slot(
            i,
            handsTogether: _handsTogether(prerequisiteSatisfied: {'C_MAJOR'}),
          ),
      ];

      expect(_find('hands_together_stall', slots), hasLength(1));
    });

    test('another material hands together does not close the wait', () {
      final slots = [
        for (var i = 0; i < 17; i++)
          _slot(
            i,
            winner: i == 2
                ? _trace(
                    _exercise(tonic: 'G', hands: HandConfiguration.together),
                  )
                : null,
            handsTogether: _handsTogether(prerequisiteSatisfied: {'C_MAJOR'}),
          ),
      ];

      expect(_find('hands_together_stall', slots), hasLength(1));
    });

    test('selecting the ready material closes the wait', () {
      final slots = [
        for (var i = 0; i < 17; i++)
          _slot(
            i,
            winner: i == 2
                ? _trace(_exercise(hands: HandConfiguration.together))
                : null,
            handsTogether: _handsTogether(prerequisiteSatisfied: {'C_MAJOR'}),
          ),
      ];

      expect(_find('hands_together_stall', slots), isEmpty);
    });
  });

  group('guidance regression', () {
    test(
      'one supported attempt followed by independence is not persistent',
      () {
        final slots = [
          _slot(
            0,
            winner: _trace(_exercise(guidance: GuidanceContext.unguided)),
          ),
          _slot(
            1,
            winner: _trace(
              _exercise(guidance: GuidanceContext.continuouslyCued),
            ),
            outcome: _outcome(retrieval: FactualRetrieval.notTested),
          ),
          _slot(
            2,
            winner: _trace(_exercise(guidance: GuidanceContext.unguided)),
          ),
        ];

        expect(_find('guidance_regression', slots), isEmpty);
      },
    );

    test('a retrieval failure explains later support', () {
      final slots = [
        _slot(0, winner: _trace(_exercise(guidance: GuidanceContext.unguided))),
        _slot(
          1,
          winner: _trace(_exercise(guidance: GuidanceContext.unguided)),
          outcome: _outcome(retrieval: FactualRetrieval.failed),
        ),
        _slot(
          2,
          winner: _trace(_exercise(guidance: GuidanceContext.continuouslyCued)),
        ),
      ];

      expect(_find('guidance_regression', slots), isEmpty);
    });

    test('support that remains elevated without failure is reported', () {
      final slots = [
        _slot(0, winner: _trace(_exercise(guidance: GuidanceContext.unguided))),
        for (var i = 1; i < 4; i++)
          _slot(
            i,
            winner: _trace(
              _exercise(guidance: GuidanceContext.continuouslyCued),
            ),
            outcome: _outcome(retrieval: FactualRetrieval.notTested),
          ),
      ];

      expect(_find('guidance_regression', slots), hasLength(1));
    });
  });

  group('run-shape observations', () {
    test('below-frontier share distinguishes either side of the boundary', () {
      expect(
        _find('below_frontier_share', [
          for (var i = 0; i < 10; i++)
            _slot(
              i,
              winner: _trace(
                _exercise(),
                realization: i < 2
                    ? RealizationRank.surpassed
                    : RealizationRank.holding,
              ),
            ),
        ]),
        hasLength(1),
      );
      expect(
        _find('below_frontier_share', [
          for (var i = 0; i < 10; i++)
            _slot(
              i,
              winner: _trace(
                _exercise(),
                realization: i == 0
                    ? RealizationRank.surpassed
                    : RealizationRank.holding,
              ),
            ),
        ]),
        isEmpty,
      );
    });

    test(
      'material concentration distinguishes either side of the boundary',
      () {
        const alternatives = ['G', 'D', 'A', 'E', 'B', 'F', 'Bb'];
        List<TrajectorySlot> slots(int repeated) => [
          for (var i = 0; i < 10; i++)
            _slot(
              i,
              winner: _trace(
                _exercise(
                  tonic: i < repeated ? 'C' : alternatives[i - repeated],
                ),
              ),
            ),
        ];

        expect(_find('material_concentration', slots(4)), hasLength(1));
        expect(_find('material_concentration', slots(3)), isEmpty);
      },
    );

    test('short cycles require two distinct alternating materials', () {
      final alternating = [
        for (var i = 0; i < 6; i++)
          _slot(i, winner: _trace(_exercise(tonic: i.isEven ? 'C' : 'G'))),
      ];
      final constant = [for (var i = 0; i < 6; i++) _slot(i)];

      expect(_find('short_cycle_repetition', alternating), hasLength(1));
      expect(_find('short_cycle_repetition', constant), isEmpty);
    });

    test('material clusters require six consecutive slots', () {
      expect(
        _find('material_cluster', [for (var i = 0; i < 6; i++) _slot(i)]),
        hasLength(1),
      );
      expect(
        _find('material_cluster', [
          for (var i = 0; i < 5; i++) _slot(i),
          _slot(5, winner: _trace(_exercise(tonic: 'G'))),
        ]),
        isEmpty,
      );
    });
  });

  group('cluster descriptions', () {
    test('coordination requires both single hands before hands together', () {
      final coordinated = [
        _slot(0, winner: _trace(_exercise(hands: HandConfiguration.right))),
        _slot(1, winner: _trace(_exercise(hands: HandConfiguration.left))),
        _slot(2, winner: _trace(_exercise(hands: HandConfiguration.together))),
      ];
      final unrelated = [
        _slot(0, winner: _trace(_exercise(hands: HandConfiguration.right))),
        _slot(1, winner: _trace(_exercise(hands: HandConfiguration.together))),
      ];

      expect(describeCluster(coordinated), ClusterKind.coordinationPhase);
      expect(describeCluster(unrelated), isNot(ClusterKind.coordinationPhase));
    });
  });
}

List<Anomaly> _find(String detector, List<TrajectorySlot> slots) =>
    detectAnomalies(
      Trajectory(playerId: 'test', seed: 0, slots: slots),
      requestedSlots: slots.length,
    ).where((anomaly) => anomaly.detector == detector).toList();

TrajectorySlot _slot(
  int index, {
  CandidateTrace? winner,
  List<CandidateTrace> alternatives = const [],
  Outcome? outcome,
  Map<int, double> frontierBefore = const {},
  Map<int, double>? frontierAfter,
  double transferableBefore = 0,
  HandsTogetherStages? handsTogether,
}) {
  final selected = winner ?? _trace(_exercise());
  final result = outcome ?? _outcome();
  return TrajectorySlot(
    index: index,
    at: _at(index),
    chosen: selected.exercise,
    winner: selected,
    alternatives: alternatives,
    performedTempoBpm: selected.exercise.conditions.tempoBpm,
    outcome: result,
    managedExecution: const LearnerModel().executionWasManaged(result),
    frontierBefore: frontierBefore,
    frontierAfter: frontierAfter ?? frontierBefore,
    pacedBefore: 0,
    transferableBefore: transferableBefore,
    candidates: const CandidateStageCounts(
      generated: 1,
      evaluated: 1,
      eligible: 1,
      admitted: 1,
      selectable: 1,
    ),
    handsTogether: handsTogether ?? _handsTogether(),
  );
}

CandidateTrace _trace(
  Exercise exercise, {
  ChallengeBypass? bypass,
  RealizationRank realization = RealizationRank.unmeasured,
  double realizationFit = 0,
  bool transition = false,
}) {
  final rank = RankKey(
    tier: EligibilityTier.fullyEligible,
    coordinationTransition: transition,
    retention: 0,
    information: 0,
    diversity: 0,
    goals: 0,
    realization: realization,
    realizationFit: realizationFit,
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
      coordinationP: 1.0,
      topologyP: 0.8,
    ),
    isWithinChallengeBand: true,
    challengeBypass: bypass,
    challengeSurvived: true,
    priorityStatus: StageStatus.reached,
    rankKey: rank,
  );
}

Exercise _exercise({
  String tonic = 'C',
  HandConfiguration hands = HandConfiguration.right,
  double tempoBpm = 60,
  GuidanceContext guidance = GuidanceContext.notesPreviewedOnly,
}) => Exercise.linear(
  material: TechnicalMaterial(tonic, ScaleForm.major),
  hands: hands,
  tempoBpm: tempoBpm,
  guidance: guidance,
);

Outcome _outcome({
  bool completed = true,
  FactualRetrieval retrieval = FactualRetrieval.succeeded,
  double continuity = 1,
  double temporalStability = 1,
}) => Outcome(
  started: true,
  retrieval: retrieval,
  completed: completed,
  materialRetrieval: 1,
  pitchIntegrity: 1,
  continuity: continuity,
  temporalStability: temporalStability,
  achievedTempoRatio: 1,
  topologyAccuracy: 1,
);

HandsTogetherStages _handsTogether({
  Set<String> prerequisiteSatisfied = const {},
}) => HandsTogetherStages(
  prerequisiteSatisfied: prerequisiteSatisfied,
  eligible: const {},
  admitted: const {},
  selectable: const {},
);

DateTime _at(int minute) => DateTime.utc(2026).add(Duration(minutes: minute));
