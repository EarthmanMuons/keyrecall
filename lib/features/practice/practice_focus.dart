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

  ActiveFocus asExclusive() => ActiveFocus(
    label: label,
    strength: FocusStrength.exclusive,
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

/// A form a learner can narrow practice to.
///
/// [major] and [minor] reach both families, because asking for minor material
/// is one question and a minor triad answers it as readily as a minor scale.
/// The three minor forms are distinctions only a scale carries, so they reach
/// the scales that spell them and no arpeggios: somebody asking for harmonic
/// minor is asking about that scale, not about minor chords.
enum FocusForm { major, minor, naturalMinor, harmonicMinor, melodicMinor }

/// The form choices worth offering over [catalog].
///
/// One offered when it reaches something, so a catalog of one family or one
/// tonality is not answered with a list of choices that select nothing.
List<FocusForm> formsIn(List<TechnicalMaterial> catalog) => [
  for (final form in FocusForm.values)
    if (formFacets({form}).selectionOf(catalog).isNotEmpty) form,
];

/// The material facets [forms] comes to.
MaterialFocus formFacets(Set<FocusForm> forms) => MaterialFocus(
  scaleFormIds: {
    for (final form in forms)
      for (final scaleForm in _scaleFormsOf(form)) scaleForm.id,
  },
  arpeggioQualityIds: {
    for (final form in forms)
      for (final quality in _qualitiesOf(form)) quality.id,
  },
);

/// The form choices [focus] asked for, less the ones a broader choice already
/// covers.
///
/// What reopens the material screen on what a focus said rather than on every
/// choice that happens to be contained in it: a focus on minor material is one
/// chip, not that chip and the three minor scale forms under it.
Set<FocusForm> formsOf(MaterialFocus focus) {
  final chosen = <FocusForm>{};
  for (final form in FocusForm.values) {
    final facets = formFacets({form});
    final asked =
        facets.scaleFormIds.every(focus.scaleFormIds.contains) &&
        facets.arpeggioQualityIds.every(focus.arpeggioQualityIds.contains);
    if (asked && !chosen.any((already) => _covers(already, form))) {
      chosen.add(form);
    }
  }
  return chosen;
}

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

/// What a form choice is called on its own, rather than after a key.
String formName(FocusForm form) => switch (form) {
  FocusForm.major => 'Major',
  FocusForm.minor => 'Minor',
  FocusForm.naturalMinor => 'Natural minor',
  FocusForm.harmonicMinor => 'Harmonic minor',
  FocusForm.melodicMinor => 'Melodic minor',
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

/// The scale forms [form] asks for.
Set<ScaleForm> _scaleFormsOf(FocusForm form) => switch (form) {
  FocusForm.major => {ScaleForm.major},
  FocusForm.minor => {
    ScaleForm.naturalMinor,
    ScaleForm.harmonicMinor,
    ScaleForm.melodicMinor,
  },
  FocusForm.naturalMinor => {ScaleForm.naturalMinor},
  FocusForm.harmonicMinor => {ScaleForm.harmonicMinor},
  FocusForm.melodicMinor => {ScaleForm.melodicMinor},
};

/// The chord qualities [form] asks for, which only a tonality names.
Set<ArpeggioQuality> _qualitiesOf(FocusForm form) => switch (form) {
  FocusForm.major => {ArpeggioQuality.major},
  FocusForm.minor => {ArpeggioQuality.minor},
  _ => const {},
};

/// Whether choosing [form] already asks for everything [other] asks for.
bool _covers(FocusForm form, FocusForm other) =>
    _scaleFormsOf(other).every(_scaleFormsOf(form).contains) &&
    _qualitiesOf(other).every(_qualitiesOf(form).contains);

/// Whether [suggestion] selects some of [catalog] but not all of it.
bool _narrows(FocusSuggestion suggestion, List<TechnicalMaterial> catalog) {
  final selected = suggestion.material.selectionOf(catalog).length;
  return selected > 0 && selected < catalog.length;
}

MaterialFocus _scales() =>
    MaterialFocus(familyIds: const {TechnicalMaterial.scaleFamilyId});

MaterialFocus _arpeggios() =>
    MaterialFocus(familyIds: const {TechnicalMaterial.arpeggioFamilyId});

MaterialFocus _major() => formFacets({FocusForm.major});

MaterialFocus _minor() => formFacets({FocusForm.minor});
