import 'technical_material.dart';

/// Every root-position arpeggio with canonical fingering in both hands.
///
/// The tonic spellings match the scale catalog. Inversions remain outside the
/// supported corpus until they have their own provenance-backed records.
final List<ArpeggioMaterial> allRootPositionArpeggios = List.unmodifiable([
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
    ArpeggioMaterial(tonic, ArpeggioQuality.major),
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
    ArpeggioMaterial(tonic, ArpeggioQuality.minor),
]);

/// The deliberately small catalog used to prove heterogeneous families.
final List<ArpeggioMaterial> proofArpeggios = List.unmodifiable([
  for (final root in ['C', 'G', 'D'])
    ArpeggioMaterial(root, ArpeggioQuality.major),
  ArpeggioMaterial('C', ArpeggioQuality.minor),
]);
