import 'technical_material.dart';

/// How early a scale is conventionally introduced.
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
/// Anything the catalog does not cover is treated as the latest band, which is
/// the conservative reading of "we have no evidence about this".
AdmissionBand admissionBandOf(TechnicalMaterial material) {
  final bands = material.form == ScaleForm.major ? _majorBands : _minorBands;
  return bands[material.tonic] ?? AdmissionBand.advancedKeyboard;
}
