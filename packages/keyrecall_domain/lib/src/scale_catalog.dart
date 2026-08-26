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
final List<TechnicalMaterial> allScales = List.unmodifiable([
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
    TechnicalMaterial(tonic, ScaleForm.major),
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
      TechnicalMaterial(tonic, form),
]);

/// The reference corpus the simulation runs against.
///
/// Seven materials covering all four forms, matched note for note by the
/// Python prototype in `analysis/learner-model/simulate.py`. The pinned trace
/// digests are a cross-implementation equivalence check, so changing this list
/// makes the two implementations disagree: it is a fixture, not a product
/// decision, and what a learner is offered is [offeredScales].
final List<TechnicalMaterial> v1ScaleCatalog = List.unmodifiable([
  TechnicalMaterial('C', ScaleForm.major),
  TechnicalMaterial('G', ScaleForm.major),
  TechnicalMaterial('F', ScaleForm.major),
  TechnicalMaterial('A', ScaleForm.naturalMinor),
  TechnicalMaterial('D', ScaleForm.harmonicMinor),
  TechnicalMaterial('F#', ScaleForm.harmonicMinor),
  TechnicalMaterial('E', ScaleForm.melodicMinor),
]);
