import 'technical_material.dart';

/// The deliberately small catalog used to prove heterogeneous families.
final List<ArpeggioMaterial> proofArpeggios = List.unmodifiable([
  for (final root in ['C', 'G', 'D'])
    ArpeggioMaterial(root, ArpeggioQuality.major),
]);
