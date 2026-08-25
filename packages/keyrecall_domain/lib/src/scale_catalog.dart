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

/// The scales V1 offers a learner.
///
/// Deliberately smaller than [allScales], and for a pedagogical reason rather
/// than a technical one: these cover the conventional right-hand family, F
/// major's thumb exception, the left-hand variants, the natural-minor
/// relationships, and the harmonic minor's raised seventh, without asking
/// somebody still building basic fluency to learn the black-key entry patterns
/// at the same time.
///
/// Fixed-form melodic minor is held back for now: it is the least familiar of
/// the four forms and adds nothing to that progression yet.
///
/// A stopgap, and the wrong long-term shape. Which material a learner is ready
/// for belongs in the scheduler's `REQUIRES` gate, alongside the rule that
/// hands-together work needs both hands first, so that the offered set can be
/// everything the system supports and admission can be a judgment about the
/// learner rather than a constant. Order is stable so a trace stays readable.
final List<TechnicalMaterial> offeredScales = List.unmodifiable([
  TechnicalMaterial('C', ScaleForm.major),
  TechnicalMaterial('G', ScaleForm.major),
  TechnicalMaterial('D', ScaleForm.major),
  TechnicalMaterial('F', ScaleForm.major),
  TechnicalMaterial('A', ScaleForm.major),
  TechnicalMaterial('E', ScaleForm.major),
  TechnicalMaterial('Bb', ScaleForm.major),
  TechnicalMaterial('A', ScaleForm.naturalMinor),
  TechnicalMaterial('E', ScaleForm.naturalMinor),
  TechnicalMaterial('D', ScaleForm.naturalMinor),
  TechnicalMaterial('C', ScaleForm.naturalMinor),
  TechnicalMaterial('A', ScaleForm.harmonicMinor),
  TechnicalMaterial('E', ScaleForm.harmonicMinor),
  TechnicalMaterial('D', ScaleForm.harmonicMinor),
]);
