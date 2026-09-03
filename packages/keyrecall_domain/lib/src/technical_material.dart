import 'package:meta/meta.dart';

import 'competency.dart';

/// A scale form supported by V1.
///
/// The catalog is deliberately open-ended: forms are an initial catalog rather
/// than a closed set, and each new form needs its own topology competency.
enum ScaleForm {
  major('MAJOR', Competency.majorScaleTopology),
  naturalMinor('NATURAL_MINOR', Competency.naturalMinorTopology),
  harmonicMinor('HARMONIC_MINOR', Competency.harmonicMinorTopology),

  /// Fixed-form melodic minor: the same ascending form in both directions.
  melodicMinor('MELODIC_MINOR', Competency.melodicMinorTopology);

  const ScaleForm(this.id, this.topologyCompetency);

  /// Stable identifier used in [TechnicalMaterial.materialId] and traces.
  final String id;

  /// The topology competency this form loads on.
  final Competency topologyCompetency;

  /// The form with the given [id].
  ///
  /// Throws [ArgumentError] when no form matches.
  static ScaleForm fromId(String id) => values.firstWhere(
    (form) => form.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown scale form'),
  );
}

/// What is being played, independent of how it is played.
///
/// Material identity deliberately excludes hand, tempo, octaves, direction,
/// and guidance, so one scale has a single memory state while its right-hand,
/// left-hand, and hands-together performances carry separate execution state.
///
/// The tonic participates directly in [materialId], which persisted records
/// key on, so it must already be canonical: `F#` and `f#` and `F♯` would
/// otherwise be three different materials. Construction rejects anything else
/// rather than normalizing it, because silently repairing input here would
/// hide the upstream bug that produced it. Normalizing user or file input is
/// a parsing concern, and belongs at that boundary.
@immutable
class TechnicalMaterial {
  /// The family resolver responsible for this material.
  static const String scaleFamilyId = 'SCALE';

  /// The tonic's canonical letter name, such as `C` or `F#`.
  final String tonic;

  /// The scale form built on [tonic].
  final ScaleForm form;

  /// Throws [ArgumentError] if [tonic] is not already canonical.
  TechnicalMaterial(this.tonic, this.form) {
    if (!isCanonicalTonic(tonic)) {
      throw ArgumentError.value(
        tonic,
        'tonic',
        'must be an uppercase letter A through G, optionally followed by a '
            'single ASCII "#" or "b"',
      );
    }
  }

  /// Whether [tonic] is written the one way this domain accepts.
  ///
  /// An uppercase letter `A` through `G`, optionally followed by a single
  /// ASCII `#` or `b`. Deliberately narrow: it covers every standard key
  /// signature without admitting double accidentals, Unicode accidentals,
  /// surrounding whitespace, or case variants.
  static bool isCanonicalTonic(String tonic) {
    if (tonic.isEmpty || tonic.length > 2) return false;
    final letter = tonic.codeUnitAt(0);
    if (letter < 0x41 || letter > 0x47) return false;
    if (tonic.length == 1) return true;
    return tonic[1] == '#' || tonic[1] == 'b';
  }

  /// Stable identifier for this material, such as `F#_HARMONIC_MINOR`.
  String get materialId => '${tonic}_${form.id}';

  /// The material-family identity used by curriculum requirements.
  String get familyId => scaleFamilyId;

  @override
  bool operator ==(Object other) =>
      other is TechnicalMaterial && other.tonic == tonic && other.form == form;

  @override
  int get hashCode => Object.hash(tonic, form);

  @override
  String toString() => materialId;
}

/// How many sharps or flats the key signature of [material] is written with.
///
/// Positive counts sharps, negative counts flats, as engraving conventionally
/// numbers them.
///
/// Every minor form takes the natural minor's signature, which is the relative
/// major's. That is the convention rather than a simplification: the raised
/// seventh of harmonic minor and the raised sixth and seventh of melodic minor
/// are written as accidentals where they occur, precisely because they are
/// alterations of the key rather than part of it. A staff drawn this way says
/// what a printed scale book says.
///
/// Throws [ArgumentError] for a tonic no standard signature covers. The
/// catalog's twelve are all covered; the guard is for a thirteenth arriving
/// without anyone deciding how to write it.
int keySignatureFifths(TechnicalMaterial material) {
  final signatures = material.form == ScaleForm.major
      ? _majorFifths
      : _minorFifths;
  final fifths = signatures[material.tonic];
  if (fifths == null) {
    throw ArgumentError.value(
      material.tonic,
      'tonic',
      'no standard key signature for this tonic in ${material.form.id}',
    );
  }
  return fifths;
}

/// Sharps and flats for each major tonic, around the circle of fifths.
const Map<String, int> _majorFifths = {
  'Cb': -7,
  'Gb': -6,
  'Db': -5,
  'Ab': -4,
  'Eb': -3,
  'Bb': -2,
  'F': -1,
  'C': 0,
  'G': 1,
  'D': 2,
  'A': 3,
  'E': 4,
  'B': 5,
  'F#': 6,
  'C#': 7,
};

/// The same circle, three letters round: every minor takes its relative
/// major's signature.
const Map<String, int> _minorFifths = {
  'Ab': -7,
  'Eb': -6,
  'Bb': -5,
  'F': -4,
  'C': -3,
  'G': -2,
  'D': -1,
  'A': 0,
  'E': 1,
  'B': 2,
  'F#': 3,
  'C#': 4,
  'G#': 5,
  'D#': 6,
  'A#': 7,
};
