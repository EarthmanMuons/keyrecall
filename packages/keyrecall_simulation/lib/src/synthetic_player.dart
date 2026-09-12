import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'python_compatible_random.dart';

/// A player, described by what they do rather than by the numbers an outcome
/// happens to need.
///
/// The distinction from [SyntheticProfile] matters: that one samples an outcome
/// from a hidden ability and reports achieved tempo as a quality score in
/// `[0, 1]`, so no learner it expresses ever plays faster than asked. A person
/// plays at the speed comfortable for them, and what the app asked for is a
/// suggestion.
///
/// So this receives the exercise and answers what happened. Requested and
/// performed tempo are separate quantities throughout, related by
/// [tempoCompliance].
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

  /// How often they ignore the count-in and play at their own pace anyway,
  /// in `[0, 1]`.
  ///
  /// [tempoCompliance] is a disposition, and a constant one describes somebody
  /// who misses the request by the same proportion every time. The learner the
  /// device sittings found is not that: they follow the count-in nearly always
  /// and occasionally play a scale they find easy at the speed they actually
  /// play it. Only the second kind of attempt is clean, fast and above the
  /// request at once, which is what opens a tempo probe, so no constant
  /// compliance can express them.
  final double sprintProbability;

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

  /// How much a motor opportunity costs at the moment it happens, in logits.
  ///
  /// Where localized difficulty comes from. A crossing, a reversal, or an
  /// octave join is a moment of an exercise rather than a property of it, so a
  /// player with this turned up is somebody whose playing breaks in a
  /// particular place rather than somebody who plays uniformly worse.
  ///
  /// Localized in acquisition transcripts. Ordinary aggregate performances
  /// read the same cost at the hardest opportunity the exercise contains.
  final double opportunityPenalty;

  /// What each material family adds to execution, in logits.
  ///
  /// Keyed by [TechnicalMaterial.scaleFamilyId] and
  /// [TechnicalMaterial.arpeggioFamilyId]. A player is rarely equally at home
  /// in both, and the scheduler now allocates across them from one adaptive
  /// system, so a run where the two are indistinguishable cannot say whether
  /// strength in one is being read as strength in the other.
  ///
  /// **The player transfers nothing between families.** Ability is learned per
  /// hand and family, so arpeggio practice never improves a scale here. Any
  /// transfer a run shows is the scheduler's, which is the only way to ask
  /// about it.
  final Map<String, double> familyAbility;

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

  /// How long a break takes to cost half of what practice gained in
  /// execution, in days, or null for somebody who does not lose it.
  ///
  /// Elapsed calendar time rather than sittings missed, so it means the same
  /// thing as the learner model's own decay and a two-day gap and a two-month
  /// one are the same question asked at two scales.
  ///
  /// **What was gained, not what they came with.** Ability slips back toward
  /// the value this player started at and stops there, so forgetting undoes
  /// practice and cannot invent a learner worse than the one who first sat down.
  /// The bound also keeps decay away from negative abilities, where decay toward
  /// zero would quietly improve somebody.
  final double? retentionHalfLifeDays;

  /// The same, for how well the material is known.
  ///
  /// Separate because retrieval and execution are separate channels
  /// everywhere else, and a returner who still has the hands but has lost the
  /// notes is the ordinary case rather than an exotic one.
  final double? familiarityHalfLifeDays;

  /// How much practice at the edge of this player's ability improves it.
  ///
  /// Kept small and explicit. A player who never improves cannot show whether
  /// the scheduler notices improvement, and one who improves quickly hides
  /// whether it notices anything else.
  ///
  /// Separate from starting ability on purpose, so that "weak" and "slow to
  /// improve" are two hypotheses rather than one. A calibration that could not
  /// tell them apart would encode low skill as an inability to learn.
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
    this.sprintProbability = 0,
    this.spanPenalty = 0.4,
    this.opportunityPenalty = 0,
    this.familyAbility = const {},
    this.materialFamiliarity = const {},
    this.noise = 0.10,
    this.learningRate = 0.01,
    this.retentionHalfLifeDays,
    this.familiarityHalfLifeDays,
  });

  /// This player with one or two knobs turned, for asking what a single trait
  /// is responsible for.
  SyntheticPlayer copyWith({
    String? id,
    PlacementTier? placement,
    double? naturalTempoRightBpm,
    double? naturalTempoLeftBpm,
    double? tempoCompliance,
    double? sprintProbability,
    double? rightHandAbility,
    double? leftHandAbility,
    double? handsTogetherAbility,
    double? spanPenalty,
    double? opportunityPenalty,
    Map<String, double>? familyAbility,
    double? familiarity,
    Map<String, double>? materialFamiliarity,
    double? noise,
    double? learningRate,
    double? retentionHalfLifeDays,
    double? familiarityHalfLifeDays,
  }) => SyntheticPlayer(
    id: id ?? this.id,
    placement: placement ?? this.placement,
    naturalTempoRightBpm: naturalTempoRightBpm ?? this.naturalTempoRightBpm,
    naturalTempoLeftBpm: naturalTempoLeftBpm ?? this.naturalTempoLeftBpm,
    tempoCompliance: tempoCompliance ?? this.tempoCompliance,
    sprintProbability: sprintProbability ?? this.sprintProbability,
    rightHandAbility: rightHandAbility ?? this.rightHandAbility,
    leftHandAbility: leftHandAbility ?? this.leftHandAbility,
    handsTogetherAbility: handsTogetherAbility ?? this.handsTogetherAbility,
    spanPenalty: spanPenalty ?? this.spanPenalty,
    opportunityPenalty: opportunityPenalty ?? this.opportunityPenalty,
    familyAbility: familyAbility ?? this.familyAbility,
    familiarity: familiarity ?? this.familiarity,
    materialFamiliarity: materialFamiliarity ?? this.materialFamiliarity,
    noise: noise ?? this.noise,
    learningRate: learningRate ?? this.learningRate,
    retentionHalfLifeDays: retentionHalfLifeDays ?? this.retentionHalfLifeDays,
    familiarityHalfLifeDays:
        familiarityHalfLifeDays ?? this.familiarityHalfLifeDays,
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

  final Map<(HandConfiguration, String), double> _ability = {};
  final Map<String, double> _familiarity;
  DateTime? _restedAt;

  PlayerState(this.player) : _familiarity = {...player.materialFamiliarity};

  /// What this player came in able to do with [hands] on [family].
  double startingAbilityOf(HandConfiguration hands, String family) =>
      switch (hands) {
        HandConfiguration.right => player.rightHandAbility,
        HandConfiguration.left => player.leftHandAbility,
        HandConfiguration.together => player.handsTogetherAbility,
      } +
      (player.familyAbility[family] ?? 0);

  /// Ages this player to [at], losing whatever the gap since the last call
  /// costs them.
  ///
  /// The first call sets the clock and costs nothing, so a run that never
  /// calls this has a player who never forgets and a player with no half-life
  /// is unaffected either way.
  ///
  /// Exponential in elapsed time, which is what makes a reading free: decay
  /// composes exactly, so advancing to an instant twice, or in two steps,
  /// leaves the same player as advancing to it once. A held-out assessment can
  /// therefore age the player to its own moment without the practice slot at
  /// that moment paying for it again.
  void restUntil(DateTime at) {
    final since = _restedAt;
    _restedAt = at;
    if (since == null) return;
    final days =
        at.difference(since).inMicroseconds / Duration.microsecondsPerDay;
    if (days <= 0) return;

    double slipped(double current, double toward, double? halfLifeDays) =>
        halfLifeDays == null || halfLifeDays <= 0
        ? current
        : toward +
              (current - toward) *
                  math.pow(0.5, days / halfLifeDays).toDouble();

    for (final key in _ability.keys) {
      _ability[key] = slipped(
        _ability[key]!,
        startingAbilityOf(key.$1, key.$2),
        player.retentionHalfLifeDays,
      );
    }
    for (final materialId in _familiarity.keys) {
      _familiarity[materialId] = slipped(
        _familiarity[materialId]!,
        player.materialFamiliarity[materialId] ?? player.familiarity,
        player.familiarityHalfLifeDays,
      );
    }
  }

  /// How well this player currently executes [family] with [hands].
  double abilityOf(HandConfiguration hands, String family) =>
      _ability[(hands, family)] ??= startingAbilityOf(hands, family);

  /// Execution ability after pace, span, and motor opportunity costs.
  ///
  /// A position reads its own opportunity; an aggregate performance reads the
  /// hardest one. Omitting performed tempo removes pace strain.
  double executionEffortFor(
    Exercise exercise, {
    int? momentIndex,
    double? performedTempoBpm,
  }) {
    final conditions = exercise.conditions;
    final natural = naturalTempoFor(conditions.hands);
    final strain = math.max(
      0.0,
      math.log((performedTempoBpm ?? natural) / natural),
    );
    final meetsOpportunity = exercise.opportunitySites.any(
      (site) => momentIndex == null || site.momentIndex == momentIndex,
    );
    return abilityOf(conditions.hands, exercise.material.familyId) -
        3.0 * strain -
        player.spanPenalty * (conditions.octaves - 1) -
        (meetsOpportunity ? player.opportunityPenalty : 0);
  }

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

  /// The tempo this player played the last exercise at.
  ///
  /// Held rather than recomputed, because a sprint is drawn once and asking
  /// again would answer about a different attempt.
  double get lastPerformedTempoBpm => _lastPerformedTempoBpm;
  double _lastPerformedTempoBpm = 0;

  /// The tempo this player plays [exercise] at, sprinting or not.
  ///
  /// A geometric blend of what was asked and what is comfortable, so
  /// compliance reads the same in both directions: a follower plays what the
  /// count-in says, somebody who ignores it plays their own pace, and the
  /// people in between drift toward comfort by a fixed proportion of the
  /// distance in log tempo. A sprint is that same person taking none of the
  /// request for one attempt.
  double performedTempoFor(Exercise exercise, {bool sprinting = false}) {
    final requested = exercise.conditions.tempoBpm;
    final natural = naturalTempoFor(exercise.conditions.hands);
    final compliance = sprinting ? 0.0 : player.tempoCompliance.clamp(0.0, 1.0);
    return math.exp(
      compliance * math.log(requested) + (1 - compliance) * math.log(natural),
    );
  }

  /// What this player does when asked for [exercise].
  ///
  /// A held-out assessment sets [practising] false: the attempt is observed
  /// rather than lived, so it teaches nothing and leaves no trace behind it.
  /// Anything a run reads afterwards has to describe the practice sequence,
  /// not the question that was asked outside it.
  Outcome play(
    Exercise exercise,
    PythonCompatibleRandom rng, {
    bool practising = true,
  }) {
    final conditions = exercise.conditions;
    final materialId = exercise.material.materialId;
    // Every draw an attempt could need, taken before anything branches on
    // them, so the same exercise consumes the same stream whatever the player's
    // state does. Paired experiments need that: a branch that skips a draw
    // moves the noise of everything after it.
    final sprintDraw = rng.nextDouble();
    final motorZ = rng.nextGaussian(0, 1);
    final retrievalDraw = rng.nextDouble();
    final startDraw = rng.nextDouble();
    final completionDraw = rng.nextDouble();
    final retrievalZ = rng.nextGaussian(0, 1);
    final pitchZ = rng.nextGaussian(0, 1);
    final continuityZ = rng.nextGaussian(0, 1);
    final stabilityZ = rng.nextGaussian(0, 1);
    final topologyZ = rng.nextGaussian(0, 1);
    final coordinationZ = rng.nextGaussian(0, 1);

    final sprinting = sprintDraw < player.sprintProbability;
    final performed = performedTempoFor(exercise, sprinting: sprinting);
    if (practising) _lastPerformedTempoBpm = performed;
    final natural = naturalTempoFor(conditions.hands);

    double noisy(double center, double z) =>
        (center + z * player.noise).clamp(0.0, 1.0);

    // Playing above your comfortable pace is what costs; playing below it is
    // free, because nobody struggles to play a scale slowly. Span costs
    // whatever the player says it costs.
    final strain = math.max(0.0, math.log(performed / natural));
    final effort = executionEffortFor(exercise, performedTempoBpm: performed);
    final motorQuality = _sigmoid(effort + motorZ * player.noise);

    // Whether the notes come. Cueing supplies them, so it separates knowing a
    // scale from being able to produce it, which is the distinction the whole
    // guidance ladder rests on.
    final known = familiarityOf(materialId);
    final retrievalSucceeded = retrievalDraw < known;
    final retrieval = exercise.guidance.isRetrievalObserved
        ? (retrievalSucceeded
              ? FactualRetrieval.succeeded
              : FactualRetrieval.failed)
        : FactualRetrieval.notTested;
    final supplied = 1.0 - exercise.guidance.retrievalDemand;
    final started = retrievalSucceeded || startDraw < supplied;

    if (!started) {
      return Outcome(
        started: false,
        retrieval: retrieval,
        completed: false,
        materialRetrieval: noisy(known, retrievalZ),
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
    final pitchIntegrity = noisy(
      available * (0.85 + 0.15 * motorQuality),
      pitchZ,
    );
    // Falling apart is a consequence of how the attempt is going rather than
    // a tax on every attempt. The unconditional nine-in-ten draw this replaced
    // put a ceiling of ninety per cent on any player's completion, which a
    // device sitting of thirty-five clean attempts is already enough to
    // refute; squaring what is left makes an attempt fail only when quality is
    // genuinely low, and rarely for somebody executing well.
    final completed =
        completionDraw < 1 - math.pow(1 - motorQuality, 2).toDouble();

    // Hands together only. Coordination degrades with strain rather than with
    // the hands' own ability, because the failure it names is the two hands
    // disagreeing about where the beat is.
    final coordination = conditions.hands == HandConfiguration.together
        ? noisy(
            _sigmoid(
              abilityOf(conditions.hands, exercise.material.familyId) -
                  2.0 * strain,
            ),
            coordinationZ,
          )
        : null;

    if (practising) {
      practiseExecution(exercise, motorQuality, completed: completed);
    }

    return Outcome(
      started: true,
      retrieval: retrieval,
      completed: completed,
      materialRetrieval: noisy(available, retrievalZ),
      pitchIntegrity: pitchIntegrity,
      continuity: noisy(motorQuality, continuityZ),
      temporalStability: noisy(motorQuality, stabilityZ),
      achievedTempoRatio: performed / conditions.tempoBpm,
      topologyAccuracy: noisy(available, topologyZ),
      coordination: coordination,
    );
  }

  /// What an attempt of this quality teaches the person.
  ///
  /// **Practice below the quality the model credits still improves them.** A
  /// frontier is what KeyRecall has been shown, and improvement is what happened
  /// to the player. Gating this on demonstrated execution would make low
  /// starting ability into an inability to learn.
  ///
  /// Graded, and largest where the task sits at the edge of what they can do.
  /// An attempt that falls apart teaches little, one they find trivial teaches
  /// little else, and an attempt that broke down before the end is worth half
  /// of one that held together. Nothing is learned from a scale that never
  /// started.
  ///
  /// No ceiling is needed. As ability grows the same task is executed better,
  /// which moves it away from the edge, so improvement slows unless the
  /// scheduler keeps asking for something harder.
  ///
  /// The curve is **a shape assumption of this player model**, not a claim
  /// about how people learn the piano: motor quality is what the simulation can
  /// see, and it is not the same quantity as pedagogical challenge.
  void practiseExecution(
    Exercise exercise,
    double motorQuality, {
    required bool completed,
  }) {
    final atTheEdge = 4 * motorQuality * (1 - motorQuality);
    final gain = player.learningRate * atTheEdge * (completed ? 1.0 : 0.5);
    final key = (exercise.conditions.hands, exercise.material.familyId);
    _ability[key] = abilityOf(key.$1, key.$2) + gain;
    final materialId = exercise.material.materialId;
    _familiarity[materialId] = math.min(0.99, familiarityOf(materialId) + gain);
  }
}

double _sigmoid(double logit) => 1.0 / (1.0 + math.exp(-logit));
