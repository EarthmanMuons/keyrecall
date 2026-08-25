import 'package:meta/meta.dart';

import 'guidance_context.dart';

/// How much of the material an attempt is told in advance.
///
/// Prospective pitch information: what the learner knows about notes they have
/// not played yet. Ordinal, unlike the modality it arrives in.
enum PitchCue {
  /// Nothing is supplied. What the learner plays comes from memory.
  none('NONE'),

  /// The first note only, so an attempt can begin from the right place.
  startOnly('START_ONLY'),

  /// A bounded window ahead of where the learner is.
  limitedLookahead('LIMITED_LOOKAHEAD'),

  /// The whole sequence.
  full('FULL');

  const PitchCue(this.id);

  /// Identifier this value will be persisted under.
  final String id;

  /// Whether any of the material is supplied before it is played.
  bool get suppliesMaterial => this != PitchCue.none;
}

/// How a supplied pitch cue is presented.
///
/// Deliberately not ordinal: a keyboard diagram and staff notation are two
/// representations of the same material, and notation adds a decoding step
/// that for a weak reader is load rather than help. Only meaningful when
/// something is being supplied, which is why [PresentationConditions] refuses
/// a modality without a cue.
enum CueModality {
  /// Marked keys on a keyboard diagram.
  keyboard('KEYBOARD'),

  /// Staff notation, which supplies the material through a reading step.
  staff('STAFF'),

  /// Both at once, which gives two routes to the same answer and makes what
  /// an attempt observed harder to attribute.
  keyboardAndStaff('KEYBOARD_AND_STAFF');

  const CueModality(this.id);

  /// Identifier this value will be persisted under.
  final String id;

  /// Whether reading the cue is itself a task the attempt then observes.
  bool get demandsNotationDecoding => this != CueModality.keyboard;
}

/// How much of the execution an attempt is told in advance.
///
/// Separate from [PitchCue] because knowing the next pitch is not knowing how
/// to reach it: a learner can be certain the note is F♯ and still not recall
/// whether the crossing is the third finger or the fourth.
enum MotorCue {
  /// Nothing about execution is supplied.
  none('NONE'),

  /// Fingering is shown.
  fingering('FINGERING');

  const MotorCue(this.id);

  /// Identifier this value will be persisted under.
  final String id;
}

/// What the learner is shown of their own playing while they play.
///
/// Retrospective, so none of it supplies material in advance. It still changes
/// what an attempt observes: an evaluated attempt can be repaired note by note
/// as it goes, which is practice rather than recall, and even a neutral echo
/// gives sensory confirmation that playing blind does not.
enum PerformanceFeedback {
  /// The learner sees nothing of what they played.
  none('NONE'),

  /// What was played is shown, unjudged. The learner still has to know
  /// whether it was right.
  neutralEcho('NEUTRAL_ECHO'),

  /// What was played is shown and marked right or wrong, so errors can be
  /// corrected during the attempt.
  evaluative('EVALUATIVE');

  const PerformanceFeedback(this.id);

  /// Identifier this value will be persisted under.
  final String id;

  /// Whether the learner is told, during the attempt, that something was
  /// wrong.
  bool get judgesDuringAttempt => this == PerformanceFeedback.evaluative;
}

/// How much of the requested pulse the app supplies.
///
/// Its own axis: it changes execution and timing support rather than how much
/// of the material has to be retrieved, so coupling it to a guidance rung
/// would move two variables at once.
enum TempoSupport {
  /// The tempo is stated and nothing sounds it.
  none('NONE'),

  /// A count-in establishes the pulse and then stops, leaving the learner to
  /// hold it. Carries no pitch information, so it is not a cue.
  countInOnly('COUNT_IN_ONLY'),

  /// A click runs throughout, which makes holding the pulse easier and is
  /// therefore support rather than a neutral frame.
  metronomeThroughout('METRONOME_THROUGHOUT');

  const TempoSupport(this.id);

  /// Identifier this value will be persisted under.
  final String id;
}

/// What information an attempt was given, on four independent channels.
///
/// Facts about the attempt, not a second scheduler. The scheduler names a
/// coarse guidance rung; practice policy turns that into these channels, and
/// the learner model can eventually distinguish conditions the rung alone
/// cannot: playing from a full score with fingering is not playing from a
/// score, which is not playing from memory while watching notes appear, which
/// is not playing blind.
///
/// Which surfaces are on screen is not recorded here. A staff that shows
/// nothing but its clef supplies nothing, and a keyboard that lights up as the
/// learner plays supplies nothing either, so withdrawal takes information away
/// rather than taking the UI away. What arrives on those surfaces is the part
/// that changes the evidence.
///
/// Nothing persists this yet. Every V1 attempt is a full keyboard cue or none,
/// no fingering, a neutral echo, and a count-in, so omitting it loses no
/// information; the wire format gains the field in the same change that makes
/// a second value reachable.
@immutable
class PresentationConditions {
  /// How much of the material is supplied before it is played.
  final PitchCue pitchCue;

  /// How that material is presented, or null when none is.
  final CueModality? cueModality;

  /// How much of the execution is supplied.
  final MotorCue motorCue;

  /// What the learner sees of their own playing.
  final PerformanceFeedback performanceFeedback;

  /// How much of the pulse is supplied.
  final TempoSupport tempoSupport;

  /// Throws [ArgumentError] when a modality is given without a cue to present
  /// or a cue is given with no way to present it.
  PresentationConditions({
    required this.pitchCue,
    required this.motorCue,
    required this.performanceFeedback,
    required this.tempoSupport,
    this.cueModality,
  }) {
    if (pitchCue.suppliesMaterial != (cueModality != null)) {
      throw ArgumentError.value(
        cueModality,
        'cueModality',
        'must be given exactly when a pitch cue supplies material',
      );
    }
  }

  /// Whether reading a cue is part of what this attempt asks for.
  bool get demandsNotationDecoding =>
      cueModality?.demandsNotationDecoding ?? false;

  /// Whether this presentation can carry an attempt under [guidance].
  ///
  /// The rung says whether material is supplied at all, and whether it stays
  /// up once the attempt starts; this says how much of it and in what form.
  /// The two have to agree about the first question. A pairing rule rather
  /// than an invariant of either value alone, so it is checked where the pair
  /// is formed.
  bool suitsGuidance(GuidanceContext guidance) =>
      pitchCue.suppliesMaterial == guidance.isMaterialSupplied;

  @override
  bool operator ==(Object other) =>
      other is PresentationConditions &&
      other.pitchCue == pitchCue &&
      other.cueModality == cueModality &&
      other.motorCue == motorCue &&
      other.performanceFeedback == performanceFeedback &&
      other.tempoSupport == tempoSupport;

  @override
  int get hashCode => Object.hash(
    pitchCue,
    cueModality,
    motorCue,
    performanceFeedback,
    tempoSupport,
  );

  @override
  String toString() =>
      'PresentationConditions(${pitchCue.id}, ${cueModality?.id ?? '-'}, '
      '${motorCue.id}, ${performanceFeedback.id}, ${tempoSupport.id})';
}
