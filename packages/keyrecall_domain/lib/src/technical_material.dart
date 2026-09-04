import 'package:meta/meta.dart';

import 'competency.dart';
import 'execution_conditions.dart';
import 'material_topology.dart';

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

/// Semitones above the tonic in each scale form.
const Map<ScaleForm, List<int>> scaleFormIntervals = {
  ScaleForm.major: [0, 2, 4, 5, 7, 9, 11],
  ScaleForm.naturalMinor: [0, 2, 3, 5, 7, 8, 10],
  ScaleForm.harmonicMinor: [0, 2, 3, 5, 7, 8, 11],
  ScaleForm.melodicMinor: [0, 2, 3, 5, 7, 9, 11],
};

/// The motor demand created by a crossing in this material family.
enum FingeringTransitionKind { scalarCrossing, arpeggioTransition }

/// Structural ordering declared by a material family.
@immutable
class MaterialProgression {
  final List<int> octaveSpans;
  final bool requiresPreviousSpanEvidence;
  final bool requiresSeparateHandsBeforeTogether;
  final Set<String> prerequisiteMaterialIds;

  MaterialProgression({
    required Iterable<int> octaveSpans,
    this.requiresPreviousSpanEvidence = false,
    this.requiresSeparateHandsBeforeTogether = true,
    Iterable<String> prerequisiteMaterialIds = const {},
  }) : octaveSpans = List.unmodifiable(octaveSpans),
       prerequisiteMaterialIds = Set.unmodifiable(prerequisiteMaterialIds) {
    if (this.octaveSpans.isEmpty ||
        this.octaveSpans.first < 1 ||
        this.octaveSpans.indexed.any(
          (entry) => entry.$1 > 0 && entry.$2 <= this.octaveSpans[entry.$1 - 1],
        )) {
      throw ArgumentError('octave spans must be positive and increasing');
    }
  }

  int? previousSpan(int span) {
    final index = octaveSpans.indexOf(span);
    return index > 0 ? octaveSpans[index - 1] : null;
  }
}

final MaterialProgression _scaleProgression = MaterialProgression(
  octaveSpans: const [1, 2],
);

/// What is being played, independent of how it is played.
///
/// Material identity deliberately excludes hand, tempo, octaves, direction,
/// and guidance, so realizations share one exact-material memory state while
/// their hand-specific performances carry separate execution state.
///
/// The tonic participates directly in [materialId], which persisted records
/// key on, so it must already be canonical: `F#` and `f#` and `F♯` would
/// otherwise be three different materials. Construction rejects anything else
/// rather than normalizing it, because silently repairing input here would
/// hide the upstream bug that produced it. Normalizing user or file input is
/// a parsing concern, and belongs at that boundary.
@immutable
sealed class TechnicalMaterial {
  /// The family resolver responsible for this material.
  static const String scaleFamilyId = 'SCALE';
  static const String arpeggioFamilyId = 'ARPEGGIO';

  const TechnicalMaterial._();

  factory TechnicalMaterial(String tonic, ScaleForm form) = ScaleMaterial;

  String get tonic;

  String get materialId;

  String get familyId;

  MaterialTopology get topology;

  Competency get topologyCompetency;

  FingeringTransitionKind get fingeringTransitionKind;

  MaterialProgression get progression;

  ScaleForm? get scaleForm => null;

  Set<Competency> executionCompetenciesFor(HandConfiguration hands);

  /// Whether [tonic] is written the one way this domain accepts.
  static bool isCanonicalTonic(String tonic) =>
      ScaleMaterial.isCanonicalTonic(tonic);
}

/// The chord quality whose tones form an arpeggio.
enum ArpeggioQuality {
  major('MAJOR', Competency.majorArpeggioTopology),
  minor('MINOR', Competency.minorArpeggioTopology);

  const ArpeggioQuality(this.id, this.topologyCompetency);

  final String id;
  final Competency topologyCompetency;

  static ArpeggioQuality fromId(String id) => values.firstWhere(
    (quality) => quality.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown quality'),
  );
}

/// Which chord tone begins an arpeggio's repeating topology.
enum ArpeggioInversion {
  root('ROOT'),
  first('FIRST'),
  second('SECOND');

  const ArpeggioInversion(this.id);

  final String id;

  static ArpeggioInversion fromId(String id) => values.firstWhere(
    (inversion) => inversion.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown inversion'),
  );
}

/// An arpeggio identified by root, quality, and inversion.
@immutable
final class ArpeggioMaterial extends TechnicalMaterial {
  @override
  final String tonic;
  final ArpeggioQuality quality;
  final ArpeggioInversion inversion;

  ArpeggioMaterial(
    this.tonic,
    this.quality, {
    this.inversion = ArpeggioInversion.root,
  }) : super._() {
    if (!ScaleMaterial.isCanonicalTonic(tonic)) {
      throw ArgumentError.value(tonic, 'tonic', 'must be canonical');
    }
  }

  @override
  String get materialId => '${tonic}_${quality.id}_${inversion.id}_ARPEGGIO';

  @override
  String get familyId => TechnicalMaterial.arpeggioFamilyId;

  @override
  late final MaterialTopology topology = switch ((quality, inversion)) {
    (ArpeggioQuality.major, ArpeggioInversion.root) => MaterialTopology(
      semitoneOffsets: const [0, 4, 7],
      letterOffsets: const [0, 2, 4],
    ),
    (ArpeggioQuality.major, ArpeggioInversion.first) => MaterialTopology(
      originSemitoneOffset: 4,
      originLetterOffset: 2,
      semitoneOffsets: const [0, 3, 8],
      letterOffsets: const [0, 2, 5],
    ),
    (ArpeggioQuality.major, ArpeggioInversion.second) => MaterialTopology(
      originSemitoneOffset: 7,
      originLetterOffset: 4,
      semitoneOffsets: const [0, 5, 9],
      letterOffsets: const [0, 3, 5],
    ),
    (ArpeggioQuality.minor, ArpeggioInversion.root) => MaterialTopology(
      semitoneOffsets: const [0, 3, 7],
      letterOffsets: const [0, 2, 4],
    ),
    (ArpeggioQuality.minor, ArpeggioInversion.first) => MaterialTopology(
      originSemitoneOffset: 3,
      originLetterOffset: 2,
      semitoneOffsets: const [0, 4, 9],
      letterOffsets: const [0, 2, 5],
    ),
    (ArpeggioQuality.minor, ArpeggioInversion.second) => MaterialTopology(
      originSemitoneOffset: 7,
      originLetterOffset: 4,
      semitoneOffsets: const [0, 5, 8],
      letterOffsets: const [0, 3, 5],
    ),
  };

  @override
  Competency get topologyCompetency => quality.topologyCompetency;

  @override
  FingeringTransitionKind get fingeringTransitionKind =>
      FingeringTransitionKind.arpeggioTransition;

  @override
  late final MaterialProgression progression = MaterialProgression(
    octaveSpans: const [1, 2, 4],
    requiresPreviousSpanEvidence: true,
    prerequisiteMaterialIds: inversion == ArpeggioInversion.root
        ? const {}
        : {
            ArpeggioMaterial(
              tonic,
              quality,
              inversion: ArpeggioInversion.root,
            ).materialId,
          },
  );

  @override
  Set<Competency> executionCompetenciesFor(HandConfiguration hands) => {
    if (hands.usesRightHand) Competency.rhArpeggioExecution,
    if (hands.usesLeftHand) Competency.lhArpeggioExecution,
    if (hands == HandConfiguration.together)
      Competency.handsTogetherCoordination,
  };

  @override
  bool operator ==(Object other) =>
      other is ArpeggioMaterial &&
      other.tonic == tonic &&
      other.quality == quality &&
      other.inversion == inversion;

  @override
  int get hashCode => Object.hash(tonic, quality, inversion);

  @override
  String toString() => materialId;
}

/// A scale identified by tonic and form.
@immutable
final class ScaleMaterial extends TechnicalMaterial {
  @override
  final String tonic;

  /// The scale form built on [tonic].
  final ScaleForm form;

  @override
  ScaleForm get scaleForm => form;

  /// Throws [ArgumentError] if [tonic] is not already canonical.
  ScaleMaterial(this.tonic, this.form) : super._() {
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
  @override
  String get materialId => '${tonic}_${form.id}';

  /// The material-family identity used by curriculum requirements.
  @override
  String get familyId => TechnicalMaterial.scaleFamilyId;

  @override
  late final MaterialTopology topology = MaterialTopology(
    semitoneOffsets: scaleFormIntervals[form]!,
    letterOffsets: List.generate(scaleFormIntervals[form]!.length, (i) => i),
  );

  @override
  Competency get topologyCompetency => form.topologyCompetency;

  @override
  FingeringTransitionKind get fingeringTransitionKind =>
      FingeringTransitionKind.scalarCrossing;

  @override
  MaterialProgression get progression => _scaleProgression;

  @override
  Set<Competency> executionCompetenciesFor(HandConfiguration hands) =>
      hands.executionCompetencies;

  @override
  bool operator ==(Object other) =>
      other is ScaleMaterial && other.tonic == tonic && other.form == form;

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
  final form = material.scaleForm;
  final signatures = form == null || form == ScaleForm.major
      ? _majorFifths
      : _minorFifths;
  final fifths = signatures[material.tonic];
  if (fifths == null) {
    throw ArgumentError.value(
      material.tonic,
      'tonic',
      'no standard key signature for this tonic in ${material.materialId}',
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
