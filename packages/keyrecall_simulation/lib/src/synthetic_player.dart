import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'python_compatible_random.dart';

/// A player, described by what they do rather than by the numbers an outcome
/// happens to need.
///
/// The distinction from [SyntheticProfile] is the point. That one samples an
/// outcome from a hidden ability, and its achieved tempo is a quality score in
/// `[0, 1]`, so no learner it can express ever plays faster than they were
/// asked to. Every tempo defect the device sittings found lived in exactly
/// that gap: a person plays at the speed that is comfortable for them, and
/// what the app asked for is a suggestion they may or may not take.
///
/// So this receives the exercise and answers what happened. Requested tempo
/// and performed tempo are separate quantities throughout, and
/// [tempoCompliance] is what relates them.
///
/// The knobs are meant to be legible rather than orthogonal. An archetype is a
/// named configuration of this one model, not its own implementation, so a
/// trajectory that goes wrong can be described as "this kind of player" rather
/// than as a coincidence of twelve coefficients.
class SyntheticPlayer {
  /// What this kind of player is called, in reports.
  final String id;

  /// What they tell the app about themselves at onboarding, which need not
  /// match what they can do.
  final PlacementTier placement;

  /// The tempo each hand is comfortable at, in beats per minute.
  ///
  /// Per hand because unevenness is ordinary: most people's left hand is
  /// slower, and a scheduler that never sees that cannot be shown to handle
  /// it. Hands together take the slower of the two.
  final double naturalTempoRightBpm;
  final double naturalTempoLeftBpm;

  /// How closely they play to the tempo they were asked for, in `[0, 1]`.
  ///
  /// One means a metronome follower, who plays sixty when asked for sixty.
  /// Zero means somebody who plays at their own pace whatever is on the
  /// screen. Between them the performed tempo is a geometric blend, so a
  /// request twice their natural pace and a request half of it are equally
  /// far off, which is how tempo actually works.
  final double tempoCompliance;

  /// How well each hand executes, in logits, before difficulty.
  final double rightHandAbility;
  final double leftHandAbility;

  /// How well the hands play together, in logits.
  ///
  /// Separate from the two hands, because coordination is its own skill and a
  /// player can have two good hands that do not agree with each other.
  final double handsTogetherAbility;

  /// How much each octave past the first costs, in logits.
  final double spanPenalty;

  /// How well they know the scales, in `[0, 1]`, as a retrievability.
  final double familiarity;

  /// Materials this player knows better or worse than [familiarity] says.
  final Map<String, double> materialFamiliarity;

  /// How much of what they can do they actually do on any given attempt.
  ///
  /// The standard deviation of the noise on every sampled quantity. Low
  /// consistency is what makes a capable player occasionally produce a bad
  /// attempt, which the scheduler has to be able to absorb without concluding
  /// anything.
  final double noise;

  /// How much a successful attempt improves the ability it exercised.
  ///
  /// Kept small and explicit. A player who never improves cannot show whether
  /// the scheduler notices improvement, and one who improves quickly hides
  /// whether it notices anything else.
  final double learningRate;

  SyntheticPlayer({
    required this.id,
    required this.placement,
    required this.naturalTempoRightBpm,
    required this.naturalTempoLeftBpm,
    required this.tempoCompliance,
    required this.rightHandAbility,
    required this.leftHandAbility,
    required this.handsTogetherAbility,
    required this.familiarity,
    this.spanPenalty = 0.4,
    this.materialFamiliarity = const {},
    this.noise = 0.10,
    this.learningRate = 0.01,
  });

  /// This player with one or two knobs turned, for asking what a single trait
  /// is responsible for.
  SyntheticPlayer copyWith({
    String? id,
    PlacementTier? placement,
    double? naturalTempoRightBpm,
    double? naturalTempoLeftBpm,
    double? tempoCompliance,
    double? rightHandAbility,
    double? leftHandAbility,
    double? handsTogetherAbility,
    double? spanPenalty,
    double? familiarity,
    Map<String, double>? materialFamiliarity,
    double? noise,
    double? learningRate,
  }) => SyntheticPlayer(
    id: id ?? this.id,
    placement: placement ?? this.placement,
    naturalTempoRightBpm: naturalTempoRightBpm ?? this.naturalTempoRightBpm,
    naturalTempoLeftBpm: naturalTempoLeftBpm ?? this.naturalTempoLeftBpm,
    tempoCompliance: tempoCompliance ?? this.tempoCompliance,
    rightHandAbility: rightHandAbility ?? this.rightHandAbility,
    leftHandAbility: leftHandAbility ?? this.leftHandAbility,
    handsTogetherAbility: handsTogetherAbility ?? this.handsTogetherAbility,
    spanPenalty: spanPenalty ?? this.spanPenalty,
    familiarity: familiarity ?? this.familiarity,
    materialFamiliarity: materialFamiliarity ?? this.materialFamiliarity,
    noise: noise ?? this.noise,
    learningRate: learningRate ?? this.learningRate,
  );

  /// A fresh mutable player of this kind, so one run never improves another.
  PlayerState begin() => PlayerState(this);
}

/// One player, mid-practice.
///
/// Ability moves as they practise, so a run is a trajectory rather than a
/// sequence of independent draws from a fixed hidden truth.
class PlayerState {
  /// The kind of player this is.
  final SyntheticPlayer player;

  final Map<HandConfiguration, double> _ability;
  final Map<String, double> _familiarity;

  PlayerState(this.player)
    : _ability = {
        HandConfiguration.right: player.rightHandAbility,
        HandConfiguration.left: player.leftHandAbility,
        HandConfiguration.together: player.handsTogetherAbility,
      },
      _familiarity = {...player.materialFamiliarity};

  /// How well this player currently executes with [hands].
  double abilityOf(HandConfiguration hands) => _ability[hands]!;

  /// How well this player currently knows [materialId].
  double familiarityOf(String materialId) =>
      _familiarity[materialId] ?? player.familiarity;

  /// The tempo this player is comfortable at with [hands].
  double naturalTempoFor(HandConfiguration hands) => switch (hands) {
    HandConfiguration.right => player.naturalTempoRightBpm,
    HandConfiguration.left => player.naturalTempoLeftBpm,
    HandConfiguration.together => math.min(
      player.naturalTempoRightBpm,
      player.naturalTempoLeftBpm,
    ),
  };

  /// The tempo this player actually plays [exercise] at.
  ///
  /// A geometric blend of what was asked and what is comfortable, so
  /// compliance reads the same in both directions: a follower plays what the
  /// count-in says, somebody who ignores it plays their own pace, and the
  /// people in between drift toward comfort by a fixed proportion of the
  /// distance in log tempo.
  double performedTempoFor(Exercise exercise) {
    final requested = exercise.conditions.tempoBpm;
    final natural = naturalTempoFor(exercise.conditions.hands);
    final compliance = player.tempoCompliance.clamp(0.0, 1.0);
    return math.exp(
      compliance * math.log(requested) + (1 - compliance) * math.log(natural),
    );
  }

  /// What this player does when asked for [exercise].
  Outcome play(Exercise exercise, PythonCompatibleRandom rng) {
    final conditions = exercise.conditions;
    final materialId = exercise.material.materialId;
    final performed = performedTempoFor(exercise);
    final natural = naturalTempoFor(conditions.hands);

    double noisy(double centre) =>
        rng.nextGaussian(centre, player.noise).clamp(0.0, 1.0);

    // Playing above your comfortable pace is what costs; playing below it is
    // free, because nobody struggles to play a scale slowly. Span costs
    // whatever the player says it costs.
    final strain = math.max(0.0, math.log(performed / natural));
    final effort =
        abilityOf(conditions.hands) -
        3.0 * strain -
        player.spanPenalty * (conditions.octaves - 1);
    final motorQuality = _sigmoid(effort + rng.nextGaussian(0, player.noise));

    // Whether the notes come. Cueing supplies them, so it separates knowing a
    // scale from being able to produce it, which is the distinction the whole
    // guidance ladder rests on.
    final known = familiarityOf(materialId);
    final retrievalSucceeded = rng.nextDouble() < known;
    final retrieval = exercise.guidance.isRetrievalObserved
        ? (retrievalSucceeded
              ? FactualRetrieval.succeeded
              : FactualRetrieval.failed)
        : FactualRetrieval.notTested;
    final supplied = 1.0 - exercise.guidance.retrievalDemand;
    final started = retrievalSucceeded || rng.nextDouble() < supplied;

    if (!started) {
      return Outcome(
        started: false,
        retrieval: retrieval,
        completed: false,
        materialRetrieval: noisy(known),
        pitchIntegrity: 0,
        continuity: 0,
        temporalStability: 0,
        achievedTempoRatio: 0,
        topologyAccuracy: 0,
      );
    }

    final available = retrievalSucceeded ? 1.0 : supplied;

    // Which notes came is mostly about whether they were known, and only
    // slightly about how well the hand moved. Wrong notes come from not
    // knowing the scale rather than from weak fingers.
    //
    // This was `0.5 + 0.5 * available * motorQuality`, dominated by motor
    // quality, and it made a weak hand a hand that plays wrong notes. So the
    // one archetype built to be uneven could not express the learner it was
    // for - somebody who knows a scale and plays it unevenly - and every
    // measurement about uneven hands was really a measurement about hands that
    // do not know the material.
    final pitchIntegrity = noisy(available * (0.85 + 0.15 * motorQuality));
    final completed = motorQuality > 0.25 && rng.nextDouble() < 0.9;

    // Hands together only. Coordination degrades with strain rather than with
    // the hands' own ability, because the failure it names is the two hands
    // disagreeing about where the beat is.
    final coordination = conditions.hands == HandConfiguration.together
        ? noisy(_sigmoid(abilityOf(conditions.hands) - 2.0 * strain))
        : null;

    if (completed && motorQuality > 0.5) _improve(exercise, motorQuality);

    return Outcome(
      started: true,
      retrieval: retrieval,
      completed: completed,
      materialRetrieval: noisy(available),
      pitchIntegrity: pitchIntegrity,
      continuity: noisy(motorQuality),
      temporalStability: noisy(motorQuality),
      achievedTempoRatio: performed / conditions.tempoBpm,
      topologyAccuracy: noisy(available),
      coordination: coordination,
    );
  }

  void _improve(Exercise exercise, double motorQuality) {
    final hands = exercise.conditions.hands;
    _ability[hands] = _ability[hands]! + player.learningRate;
    final materialId = exercise.material.materialId;
    _familiarity[materialId] = math.min(
      0.99,
      familiarityOf(materialId) + player.learningRate,
    );
  }
}

double _sigmoid(double logit) => 1.0 / (1.0 + math.exp(-logit));
