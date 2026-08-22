import 'technical_material.dart';

/// The scale materials V1 practices.
///
/// An initial catalog rather than a closed set: it covers all four supported
/// forms and enough sharp/flat variety to exercise transfer between related
/// keys. Order is stable so traces and fixtures stay comparable across runs.
final List<TechnicalMaterial> v1ScaleCatalog = List.unmodifiable([
  TechnicalMaterial('C', ScaleForm.major),
  TechnicalMaterial('G', ScaleForm.major),
  TechnicalMaterial('F', ScaleForm.major),
  TechnicalMaterial('A', ScaleForm.naturalMinor),
  TechnicalMaterial('D', ScaleForm.harmonicMinor),
  TechnicalMaterial('F#', ScaleForm.harmonicMinor),
  TechnicalMaterial('E', ScaleForm.melodicMinor),
]);
