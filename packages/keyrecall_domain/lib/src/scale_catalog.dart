import 'technical_material.dart';

/// Every scale V1 has canonical fingering for.
///
/// Twelve tonics in each of the four forms, spelled the way the fingering
/// research spells them: D flat major and C sharp minor are separate entries
/// rather than one enharmonic pair, because their fingerings are different
/// records with different provenance.
///
/// This is what the system supports, not what a learner is offered. What to
/// practice next is the scheduler's question.
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
/// Seven materials covering all four forms. The pinned trace digests hash runs
/// over exactly this list, so changing it invalidates them: it is a fixture,
/// not a product decision. Candidate generation and scheduling decide what a
/// learner is offered from the selected catalog.
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
/// Major and natural minor are the ordinary vocabulary: one shape and its
/// relative, with no altered degree to remember. The other minor forms each
/// change what "minor" means -- a raised seventh, or a raised sixth and
/// seventh -- so meeting them is learning a new concept rather than a new key.
///
/// Used to keep the vocabulary from growing faster than the base under it.
/// Nothing about difficulty: a Db major scale is harder to play than an A
/// harmonic minor, and both facts are true at once, which is why this is a
/// separate question from the admission bands.
const Set<ScaleForm> coreForms = {ScaleForm.major, ScaleForm.naturalMinor};
