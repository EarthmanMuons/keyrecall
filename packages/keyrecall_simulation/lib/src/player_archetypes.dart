import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'synthetic_player.dart';

/// The players the scheduler has to behave sensibly for.
///
/// Named configurations of one [SyntheticPlayer] model rather than separate
/// implementations, so a defect can be reported as "this kind of person" and
/// two archetypes that fail the same way are visibly the same failure.
///
/// Chosen to span the axes that have actually produced defects: how fast
/// somebody naturally plays, whether they follow the count-in, how far apart
/// their hands are, and whether what they told the app matches what they can
/// do.
abstract final class PlayerArchetypes {
  /// Somebody genuinely starting out. Slow, and the notes do not reliably
  /// come.
  static SyntheticPlayer get trueBeginner => SyntheticPlayer(
    id: 'true_beginner',
    placement: PlacementTier.beginner,
    naturalTempoRightBpm: 60,
    naturalTempoLeftBpm: 54,
    tempoCompliance: 0.85,
    rightHandAbility: -0.8,
    leftHandAbility: -1.2,
    handsTogetherAbility: -2.0,
    familiarity: 0.25,
    spanPenalty: 0.9,
    noise: 0.16,
    learningRate: 0.02,
  );

  /// A few months in. Knows the first scales, working on the rest.
  static SyntheticPlayer get developing => SyntheticPlayer(
    id: 'developing',
    placement: PlacementTier.beginner,
    naturalTempoRightBpm: 84,
    naturalTempoLeftBpm: 76,
    tempoCompliance: 0.7,
    rightHandAbility: 0.2,
    leftHandAbility: -0.2,
    handsTogetherAbility: -0.9,
    familiarity: 0.5,
    spanPenalty: 0.6,
  );

  /// Comfortable with the common keys, extending range and speed.
  static SyntheticPlayer get intermediate => SyntheticPlayer(
    id: 'intermediate',
    placement: PlacementTier.someExperience,
    naturalTempoRightBpm: 116,
    naturalTempoLeftBpm: 108,
    tempoCompliance: 0.6,
    rightHandAbility: 1.0,
    leftHandAbility: 0.8,
    handsTogetherAbility: 0.3,
    familiarity: 0.75,
    spanPenalty: 0.35,
  );

  /// Broad ownership, fast, even hands.
  static SyntheticPlayer get advanced => SyntheticPlayer(
    id: 'advanced',
    placement: PlacementTier.advanced,
    naturalTempoRightBpm: 152,
    naturalTempoLeftBpm: 144,
    tempoCompliance: 0.5,
    rightHandAbility: 2.0,
    leftHandAbility: 1.9,
    handsTogetherAbility: 1.4,
    familiarity: 0.9,
    spanPenalty: 0.2,
    noise: 0.07,
  );

  /// Plays quickly and cleanly, and called themselves a beginner.
  ///
  /// The device sittings, in the shape they kept turning out to have: a
  /// placement that understates the player, so every estimate starts low while
  /// the playing does not.
  static SyntheticPlayer get fastButPlacedLow => SyntheticPlayer(
    id: 'fast_but_placed_low',
    placement: PlacementTier.beginner,
    naturalTempoRightBpm: 126,
    naturalTempoLeftBpm: 120,
    tempoCompliance: 0.15,
    rightHandAbility: 1.2,
    leftHandAbility: 1.0,
    handsTogetherAbility: 0.4,
    familiarity: 0.7,
    spanPenalty: 0.4,
  );

  /// Plays at their own pace, whatever the count-in says.
  static SyntheticPlayer get tempoNoncompliant => SyntheticPlayer(
    id: 'tempo_noncompliant',
    placement: PlacementTier.someExperience,
    naturalTempoRightBpm: 132,
    naturalTempoLeftBpm: 126,
    tempoCompliance: 0.0,
    rightHandAbility: 1.0,
    leftHandAbility: 0.9,
    handsTogetherAbility: 0.5,
    familiarity: 0.7,
    spanPenalty: 0.35,
  );

  /// Follows the count-in, and now and then plays a scale at their own pace.
  ///
  /// Built from a device sitting rather than from a tier of ability: the
  /// attempts that opened tempo probes there were the occasional ones, played
  /// clean and well above the request, by somebody who had followed the
  /// count-in all session.
  static SyntheticPlayer get compliantThenSprints => SyntheticPlayer(
    id: 'compliant_then_sprints',
    placement: PlacementTier.someExperience,
    naturalTempoRightBpm: 132,
    naturalTempoLeftBpm: 120,
    tempoCompliance: 0.85,
    sprintProbability: 0.2,
    rightHandAbility: 1.3,
    leftHandAbility: 1.1,
    handsTogetherAbility: 0.5,
    familiarity: 0.8,
    spanPenalty: 0.3,
  );

  /// Technically reliable, and plays at their own pace whatever is asked.
  ///
  /// Built from the first device sitting rather than from a tier of ability:
  /// thirty-five attempts, every one completed, execution at the top of the
  /// measurement's range, and a played tempo that follows the requested one
  /// with a slope near a third. The archetypes that came before could not
  /// express somebody both this reliable and this self-paced, because
  /// completion carried an unconditional failure rate.
  static SyntheticPlayer get reliableSelfPaced => SyntheticPlayer(
    id: 'reliable_self_paced',
    placement: PlacementTier.beginner,
    naturalTempoRightBpm: 132,
    naturalTempoLeftBpm: 126,
    tempoCompliance: 0.35,
    rightHandAbility: 3.0,
    leftHandAbility: 2.8,
    handsTogetherAbility: 2.2,
    familiarity: 0.9,
    spanPenalty: 0.2,
    noise: 0.06,
  );

  /// A strong right hand and a left that has not kept up.
  static SyntheticPlayer get unevenHands => SyntheticPlayer(
    id: 'uneven_hands',
    placement: PlacementTier.someExperience,
    naturalTempoRightBpm: 138,
    naturalTempoLeftBpm: 76,
    tempoCompliance: 0.6,
    rightHandAbility: 1.6,
    leftHandAbility: -0.6,
    handsTogetherAbility: -0.4,
    familiarity: 0.75,
    spanPenalty: 0.35,
  );

  /// Two capable hands that do not agree with each other.
  static SyntheticPlayer get coordinationLimited => SyntheticPlayer(
    id: 'coordination_limited',
    placement: PlacementTier.someExperience,
    naturalTempoRightBpm: 126,
    naturalTempoLeftBpm: 120,
    tempoCompliance: 0.6,
    rightHandAbility: 1.4,
    leftHandAbility: 1.3,
    handsTogetherAbility: -1.8,
    familiarity: 0.8,
    spanPenalty: 0.3,
  );

  /// Practises well and loses it between sittings.
  ///
  /// The player a long-gap run needs and did not have. Every other archetype
  /// keeps whatever they gained forever, so a run across a calendar could only
  /// ever establish how the scheduler reacts to its own belief aging. This one
  /// forgets the notes faster than the hands, which is the ordinary shape of
  /// coming back after a break, and forgets both fast enough that a month off
  /// is visible in a held-out reading.
  static SyntheticPlayer get forgetfulReturner => SyntheticPlayer(
    id: 'forgetful_returner',
    placement: PlacementTier.someExperience,
    naturalTempoRightBpm: 108,
    naturalTempoLeftBpm: 100,
    tempoCompliance: 0.7,
    rightHandAbility: 0.4,
    leftHandAbility: 0.1,
    handsTogetherAbility: -0.6,
    familiarity: 0.55,
    spanPenalty: 0.45,
    learningRate: 0.05,
    retentionHalfLifeDays: 45,
    familiarityHalfLifeDays: 20,
  );

  /// Every archetype, for sweeping.
  static List<SyntheticPlayer> get all => [
    trueBeginner,
    developing,
    intermediate,
    advanced,
    fastButPlacedLow,
    tempoNoncompliant,
    compliantThenSprints,
    reliableSelfPaced,
    unevenHands,
    coordinationLimited,
    forgetfulReturner,
  ];
}
