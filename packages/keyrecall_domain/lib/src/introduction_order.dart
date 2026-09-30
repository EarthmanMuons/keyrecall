import 'technical_material.dart';

/// The 24 major and natural-minor tonalities, fewest accidentals first.
///
/// At equal complexity a major comes before a minor, then a sharp key before a
/// flat one. Each minor is placed by its own key signature rather than beside
/// its relative major. Spelled as the catalogs spell them.
const List<({String tonic, bool major})> tonalitiesByKeySignature = [
  (tonic: 'C', major: true),
  (tonic: 'A', major: false),
  (tonic: 'G', major: true),
  (tonic: 'F', major: true),
  (tonic: 'E', major: false),
  (tonic: 'D', major: false),
  (tonic: 'D', major: true),
  (tonic: 'Bb', major: true),
  (tonic: 'B', major: false),
  (tonic: 'G', major: false),
  (tonic: 'A', major: true),
  (tonic: 'Eb', major: true),
  (tonic: 'F#', major: false),
  (tonic: 'C', major: false),
  (tonic: 'E', major: true),
  (tonic: 'Ab', major: true),
  (tonic: 'C#', major: false),
  (tonic: 'F', major: false),
  (tonic: 'B', major: true),
  (tonic: 'Db', major: true),
  (tonic: 'G#', major: false),
  (tonic: 'Bb', major: false),
  (tonic: 'F#', major: true),
  (tonic: 'Eb', major: false),
];

/// [materials] in the order a fluency curriculum introduces them.
///
/// First every tonality in [tonalitiesByKeySignature] order, each as its
/// scale and then its root-position arpeggio, so neither family waits for the
/// other to be finished. Then every harmonic minor and then every melodic
/// minor, in the same minor-key order: altered forms extend a tonality rather
/// than define it. Anything else follows, in the order it was given.
List<M> inIntroductionOrder<M extends TechnicalMaterial>(
  Iterable<M> materials,
) {
  final given = materials.toList();
  final keys = [for (final material in given) _introductionKey(material)];
  final order = List.generate(given.length, (index) => index)
    ..sort((a, b) {
      for (var i = 0; i < 3; i++) {
        final byPart = keys[a][i].compareTo(keys[b][i]);
        if (byPart != 0) return byPart;
      }
      return a.compareTo(b);
    });
  return [for (final index in order) given[index]];
}

/// Stage, tonality, then family: where [material] falls in the introduction.
List<int> _introductionKey(TechnicalMaterial material) {
  final placed = switch (material) {
    ScaleMaterial(form: ScaleForm.major) => (0, true, 0),
    ScaleMaterial(form: ScaleForm.naturalMinor) => (0, false, 0),
    ScaleMaterial(form: ScaleForm.harmonicMinor) => (1, false, 0),
    ScaleMaterial(form: ScaleForm.melodicMinor) => (2, false, 0),
    ArpeggioMaterial(inversion: ArpeggioInversion.root, :final quality) => (
      0,
      quality == ArpeggioQuality.major,
      1,
    ),
    _ => null,
  };
  if (placed == null) return const [3, 0, 0];
  final (stage, major, family) = placed;
  final position = tonalitiesByKeySignature.indexWhere(
    (tonality) => tonality.tonic == material.tonic && tonality.major == major,
  );
  return position < 0 ? const [3, 0, 0] : [stage, position, family];
}
