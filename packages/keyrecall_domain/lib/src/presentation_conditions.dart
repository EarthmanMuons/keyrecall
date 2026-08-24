import 'package:meta/meta.dart';

import 'guidance_context.dart';

/// Which representation of the pitch material an attempt puts on screen.
///
/// Deliberately not ordinal. A keyboard diagram and staff notation are two
/// representations of the same pitch material, not two strengths of one cue:
/// notation supplies the material through a decoding step that a keyboard
/// diagram does not require, so for a weak reader it can add load rather than
/// remove it. Ranking them would make [PresentationConditions] look like a
/// support ladder and invite it into the scheduler's recovery topology, which
/// is [GuidanceContext]'s job and only makes sense for an ordered dimension.
///
/// V1 reaches only [none] and [keyboard]. The notation values exist so the
/// distinction is stated where the choice is made, and so the commit that
/// makes one reachable is an explicit, versioned change.
enum PitchRepresentation {
  /// Nothing on screen names the pitches.
  none('NONE'),

  /// A keyboard diagram marking the member keys.
  keyboard('KEYBOARD'),

  /// Staff notation, which supplies the material and adds a decoding demand.
  staff('STAFF'),

  /// Both at once. Two redundant routes to the same answer, which makes what
  /// an attempt observed harder to attribute; offered only deliberately.
  keyboardAndStaff('KEYBOARD_AND_STAFF');

  const PitchRepresentation(this.id);

  /// Identifier this value will be persisted under.
  ///
  /// Nothing writes it yet; see [PresentationConditions].
  final String id;

  /// Whether this representation names the pitches at all.
  bool get suppliesPitchMaterial => this != PitchRepresentation.none;

  /// Whether reading the cue is itself a task the attempt then observes.
  bool get demandsNotationDecoding =>
      this == PitchRepresentation.staff ||
      this == PitchRepresentation.keyboardAndStaff;
}

/// How much of the requested pulse the app supplies.
///
/// A separate axis from pitch guidance, and separate for the same reason
/// notation is: it changes execution and timing support rather than how much
/// of the material the learner has to retrieve. Coupling it to a guidance rung
/// would move two variables at once and make an attempt's evidence
/// unattributable.
enum TempoSupport {
  /// The tempo is stated and nothing sounds it.
  none('NONE'),

  /// A count-in establishes the pulse and then stops, leaving the learner to
  /// hold it. Carries no pitch information, so it is not guidance.
  countInOnly('COUNT_IN_ONLY'),

  /// A click runs throughout, which makes holding the pulse easier and is
  /// therefore practice support rather than a neutral frame.
  metronomeThroughout('METRONOME_THROUGHOUT');

  const TempoSupport(this.id);

  /// Identifier this value will be persisted under.
  ///
  /// Nothing writes it yet; see [PresentationConditions].
  final String id;
}

/// How a decided exercise is actually shown: pitch representation and tempo
/// support.
///
/// Chosen by practice policy when a decision becomes visible, not by the
/// scheduler. Keeping it out of [Exercise] preserves three things that depend
/// on guidance being the only presentation dimension the scheduler sees:
/// candidate generation stays at three variants per realization rather than
/// their product with representation and tempo, `oneStepMoreSupportive` keeps
/// meaning something on an ordered ladder, and notation never leaks into
/// `retrievalDemand` or realization identity.
///
/// Nothing persists this yet. Every V1 attempt is keyboard-or-none plus
/// count-in, so omitting it loses no information; the wire format gains the
/// field in the same change that makes a second value reachable, together with
/// a schema bump, an upgrade for existing records, and a place for it on the
/// durable presented decision.
@immutable
class PresentationConditions {
  /// Which pitch representation is shown.
  final PitchRepresentation pitchRepresentation;

  /// How much of the pulse is supplied.
  final TempoSupport tempoSupport;

  const PresentationConditions({
    required this.pitchRepresentation,
    required this.tempoSupport,
  });

  /// Whether this presentation can carry an attempt under [guidance].
  ///
  /// Every guidance rung except [GuidanceContext.unguided] has something to
  /// show, before the attempt or throughout it, so it needs a representation;
  /// an unguided attempt has nothing to show and must not present one. This is
  /// a pairing rule rather than an invariant of either value alone, so it is
  /// checked where the pair is formed. See `presentationFor` in the app's
  /// practice policy, which is the only place that forms one.
  bool suitsGuidance(GuidanceContext guidance) =>
      pitchRepresentation.suppliesPitchMaterial == guidance.isMaterialSupplied;

  @override
  bool operator ==(Object other) =>
      other is PresentationConditions &&
      other.pitchRepresentation == pitchRepresentation &&
      other.tempoSupport == tempoSupport;

  @override
  int get hashCode => Object.hash(pitchRepresentation, tempoSupport);

  @override
  String toString() =>
      'PresentationConditions(${pitchRepresentation.id}, ${tempoSupport.id})';
}
