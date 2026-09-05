import 'pitch_spelling.dart';
import 'technical_material.dart';

/// How early a material is conventionally introduced.
///
/// A prior taken from graded syllabi and method books, not a difficulty
/// measurement: those sources agree roughly on what to introduce first and
/// disagree about the details, so this says "a sensible place to start" and
/// nothing about latent difficulty. See
/// `docs/domain-model/material-admission.md`.
///
/// Material only. Hands, octaves, direction and tempo are execution
/// conditions, and graded syllabi bundle them with key choice in a way this
/// deliberately does not.
enum AdmissionBand {
  /// The earliest material in every source consulted.
  foundation('FOUNDATION'),

  /// Mostly transfer of established hand patterns, with new pitch material.
  earlyTransfer('EARLY_TRANSFER'),

  /// More black-key geography, or a new hand pattern, or both.
  intermediateKeyboard('INTERMEDIATE_KEYBOARD'),

  /// The material that appears substantially later in graded curricula.
  advancedKeyboard('ADVANCED_KEYBOARD');

  const AdmissionBand(this.id);

  /// Stable identifier used in traces.
  final String id;

  /// Whether this band is at least as early as [other].
  bool isAtLeastAsEarlyAs(AdmissionBand other) => index <= other.index;
}

/// Tonics by band, for the major scales.
///
/// Taken from the sources; the arpeggio bands below are derived instead.
const Map<String, AdmissionBand> _majorBands = {
  'C': AdmissionBand.foundation,
  'G': AdmissionBand.foundation,
  'F': AdmissionBand.foundation,
  'D': AdmissionBand.earlyTransfer,
  'A': AdmissionBand.earlyTransfer,
  'E': AdmissionBand.earlyTransfer,
  'Bb': AdmissionBand.earlyTransfer,
  'Eb': AdmissionBand.intermediateKeyboard,
  'B': AdmissionBand.intermediateKeyboard,
  'F#': AdmissionBand.intermediateKeyboard,
  'Ab': AdmissionBand.intermediateKeyboard,
  'Db': AdmissionBand.advancedKeyboard,
};

/// Tonics by band, for every minor form.
///
/// The form does not move the band. Which minor form to introduce first is a
/// question about topology rather than about keyboard geography, and the
/// curricula give no support for a universal natural, then harmonic, then
/// melodic ladder.
const Map<String, AdmissionBand> _minorBands = {
  'A': AdmissionBand.foundation,
  'D': AdmissionBand.foundation,
  'E': AdmissionBand.earlyTransfer,
  'G': AdmissionBand.earlyTransfer,
  'C': AdmissionBand.earlyTransfer,
  'B': AdmissionBand.intermediateKeyboard,
  'F': AdmissionBand.intermediateKeyboard,
  'F#': AdmissionBand.intermediateKeyboard,
  'C#': AdmissionBand.advancedKeyboard,
  'G#': AdmissionBand.advancedKeyboard,
  'Eb': AdmissionBand.advancedKeyboard,
  'Bb': AdmissionBand.advancedKeyboard,
};

/// Which band [material] belongs to.
///
/// Each family answers for its own material. Anything neither of them covers
/// is treated as the latest band, which is the conservative reading of "we
/// have no evidence about this": a material nobody has placed must not arrive
/// at a beginner's frontier because it happened to fall through a lookup.
AdmissionBand admissionBandOf(TechnicalMaterial material) => switch (material) {
  ScaleMaterial(:final form, :final tonic) =>
    (form == ScaleForm.major ? _majorBands : _minorBands)[tonic] ??
        AdmissionBand.advancedKeyboard,
  ArpeggioMaterial() => _arpeggioBandOf(material),
};

/// Which band an arpeggio belongs to, from the geography of its chord.
///
/// Derived rather than listed, because what changes between one root-position
/// arpeggio and the next is where the hand sits on the keyboard. A triad of
/// white keys is played with the thumb on its root; a black root is what forces
/// the second finger to start and the thumb to find a white key inside the
/// shape, which is the new motor pattern rather than a new key signature.
///
/// ```text
/// foundation             every tone is a white key
/// early transfer         white root, black keys inside the shape
/// intermediate keyboard  black root, still a white key to reach for
/// advanced keyboard      every tone is a black key
/// ```
///
/// A prior about where to start, like the scale bands beside it, and not a
/// difficulty measurement. It is provisional until the arpeggio pedagogy pass
/// in `docs/domain-model/arpeggio-domain-research.md` settles the memberships.
AdmissionBand _arpeggioBandOf(ArpeggioMaterial material) {
  final topology = material.topology;
  final origin =
      (pitchClassOf(material.tonic) + topology.originSemitoneOffset) % 12;
  final tones = {
    for (final offset in topology.semitoneOffsets) (origin + offset) % 12,
  };
  final black = tones.where(_isBlackKey).length;

  if (black == 0) return AdmissionBand.foundation;
  if (!_isBlackKey(origin)) return AdmissionBand.earlyTransfer;
  return black == tones.length
      ? AdmissionBand.advancedKeyboard
      : AdmissionBand.intermediateKeyboard;
}

const Set<int> _blackPitchClasses = {1, 3, 6, 8, 10};

bool _isBlackKey(int pitchClass) => _blackPitchClasses.contains(pitchClass);
