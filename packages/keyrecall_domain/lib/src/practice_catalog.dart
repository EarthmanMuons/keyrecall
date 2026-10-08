import 'arpeggio_catalog.dart';
import 'scale_catalog.dart';
import 'technical_material.dart';

/// Every material the app offers, across every family.
///
/// One list, so that anything checking a property of the whole catalog checks
/// the family added next along with the rest.
final List<TechnicalMaterial> allPracticeMaterials = List.unmodifiable([
  ...allScales,
  ...allRootPositionArpeggios,
]);
