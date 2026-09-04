import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'exercise_presentation.dart';

/// A focus offered by name, and what it selects.
@immutable
class FocusSuggestion {
  final String label;
  final MaterialFocus material;

  const FocusSuggestion({required this.label, required this.material});

  ActiveFocus asEmphasis() => ActiveFocus(
    label: label,
    strength: FocusStrength.emphasis,
    material: material,
  );
}

/// The focuses worth offering over [catalog].
///
/// Contextual rather than a fixed taxonomy: a suggestion that reaches nothing
/// in the active goal is not shown, and neither is one that reaches all of it,
/// because a focus that narrows nothing is what practicing normally already
/// does. What a learner can express is wider than this list; these are the
/// ones worth one tap.
List<FocusSuggestion> focusSuggestionsFor(List<TechnicalMaterial> catalog) => [
  for (final suggestion in _candidateSuggestions)
    if (_narrows(suggestion, catalog)) suggestion,
];

/// Every material family present in [catalog], in catalog order.
List<String> familyIdsIn(List<TechnicalMaterial> catalog) => [
  ...{for (final material in catalog) material.familyId},
];

/// Every scale form present in [catalog].
List<ScaleForm> scaleFormsIn(List<TechnicalMaterial> catalog) => [
  for (final form in ScaleForm.values)
    if (catalog.any((material) => material.scaleForm == form)) form,
];

/// Every chord quality present in [catalog].
List<ArpeggioQuality> arpeggioQualitiesIn(List<TechnicalMaterial> catalog) => [
  for (final quality in ArpeggioQuality.values)
    if (catalog.any(
      (material) => material is ArpeggioMaterial && material.quality == quality,
    ))
      quality,
];

/// Every key present in [catalog], in the order the catalog spells them.
List<String> tonicsIn(List<TechnicalMaterial> catalog) => [
  ...{for (final material in catalog) material.tonic},
];

/// What a family is called where a learner chooses one.
String familyName(String familyId) => switch (familyId) {
  TechnicalMaterial.scaleFamilyId => 'Scales',
  TechnicalMaterial.arpeggioFamilyId => 'Arpeggios',
  _ => familyId,
};

/// What a scale form is called on its own, rather than after a key.
String scaleFormName(ScaleForm form) => switch (form) {
  ScaleForm.major => 'Major',
  ScaleForm.naturalMinor => 'Natural minor',
  ScaleForm.harmonicMinor => 'Harmonic minor',
  ScaleForm.melodicMinor => 'Melodic minor',
};

/// What a chord quality is called on its own.
String arpeggioQualityName(ArpeggioQuality quality) => switch (quality) {
  ArpeggioQuality.major => 'Major',
  ArpeggioQuality.minor => 'Minor',
};

/// How a set of materials is described where it has no name of its own.
///
/// One material is worth naming; a handful is not, and counting them is what
/// somebody is actually deciding about.
String selectionLabel(List<TechnicalMaterial> selection) => switch (selection) {
  [] => 'No material',
  [final only] => materialName(only),
  _ => '${selection.length} materials',
};

/// Every suggestion this build knows how to offer, before the catalog decides
/// which of them mean anything.
final List<FocusSuggestion> _candidateSuggestions = [
  FocusSuggestion(label: 'Scales', material: _scales()),
  FocusSuggestion(label: 'Arpeggios', material: _arpeggios()),
  FocusSuggestion(label: 'Major material', material: _major()),
  FocusSuggestion(label: 'Minor material', material: _minor()),
];

/// Whether [suggestion] selects some of [catalog] but not all of it.
bool _narrows(FocusSuggestion suggestion, List<TechnicalMaterial> catalog) {
  final selected = suggestion.material.selectionOf(catalog).length;
  return selected > 0 && selected < catalog.length;
}

MaterialFocus _scales() =>
    MaterialFocus(familyIds: const {TechnicalMaterial.scaleFamilyId});

MaterialFocus _arpeggios() =>
    MaterialFocus(familyIds: const {TechnicalMaterial.arpeggioFamilyId});

MaterialFocus _major() => MaterialFocus(
  scaleFormIds: {ScaleForm.major.id},
  arpeggioQualityIds: {ArpeggioQuality.major.id},
);

MaterialFocus _minor() => MaterialFocus(
  scaleFormIds: {
    ScaleForm.naturalMinor.id,
    ScaleForm.harmonicMinor.id,
    ScaleForm.melodicMinor.id,
  },
  arpeggioQualityIds: {ArpeggioQuality.minor.id},
);
