import 'technical_material.dart';

/// Every scale V1 has canonical fingering for.
///
/// Twelve tonics in each of the four forms, spelled the way the fingering
/// research spells them: D flat major and C sharp minor are separate entries
/// rather than one enharmonic pair, because their fingerings are different
/// records with different provenance.
///
/// What the system supports, not what a learner is offered.
final List<ScaleMaterial> allScales = List.unmodifiable([
  for (final tonic in [
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'F#',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ])
    ScaleMaterial(tonic, ScaleForm.major),
  for (final tonic in [
    'C',
    'C#',
    'D',
    'Eb',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'Bb',
    'B',
  ])
    for (final form in [
      ScaleForm.naturalMinor,
      ScaleForm.harmonicMinor,
      ScaleForm.melodicMinor,
    ])
      ScaleMaterial(tonic, form),
]);

/// The reference corpus the simulation runs against.
///
/// Seven materials covering all four forms. A fixture rather than a product
/// decision: the pinned trace digests hash runs over exactly this list, so
/// changing it invalidates them.
final List<ScaleMaterial> v1ScaleCatalog = List.unmodifiable([
  ScaleMaterial('C', ScaleForm.major),
  ScaleMaterial('G', ScaleForm.major),
  ScaleMaterial('F', ScaleForm.major),
  ScaleMaterial('A', ScaleForm.naturalMinor),
  ScaleMaterial('D', ScaleForm.harmonicMinor),
  ScaleMaterial('F#', ScaleForm.harmonicMinor),
  ScaleMaterial('E', ScaleForm.melodicMinor),
]);

/// The forms a learner builds their sense of "a scale" out of.
///
/// Major and natural minor are the ordinary vocabulary, with no altered degree
/// to remember. Each other minor form changes what "minor" means, so meeting
/// one is learning a new concept rather than a new key.
///
/// Keeps the vocabulary from growing faster than the base under it. Nothing
/// about difficulty, which the admission bands answer separately.
const Set<ScaleForm> coreForms = {ScaleForm.major, ScaleForm.naturalMinor};
