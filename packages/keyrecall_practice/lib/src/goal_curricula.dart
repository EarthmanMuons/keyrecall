import 'package:keyrecall_domain/keyrecall_domain.dart';

/// A small set of common keys, chosen for how much keyboard it covers.
///
/// Major C, G, D, A, F, and B flat and natural minor A, E, D, and G: both of
/// the two earliest admission bands and three fingering families, the standard
/// pattern, F's right-hand exception, and B flat's black-key start. E major is
/// left out because it adds a fourth sharp and no new fingering. Each hand
/// separately over one octave, up and down, from memory, since the milestone
/// is geography and recall rather than coordination.
final Curriculum foundationsCurriculum = Curriculum(
  id: 'FOUNDATIONS',
  version: '1',
  requirements: [
    for (final material in [
      for (final tonic in ['C', 'G', 'D', 'A', 'F', 'Bb'])
        ScaleMaterial(tonic, ScaleForm.major),
      for (final tonic in ['A', 'E', 'D', 'G'])
        ScaleMaterial(tonic, ScaleForm.naturalMinor),
    ])
      for (final hands in [HandConfiguration.right, HandConfiguration.left])
        _requirement(material, hands, octaves: 1),
  ],
);

/// Every major and natural-minor key, as a scale and as a root-position
/// arpeggio, hands together over two octaves, up and down, from memory.
///
/// The altered minor forms are extensions of these tonalities and not part of
/// having them, and inversions are a later phase of the arpeggio. What each
/// version held is in `docs/system/curriculum.md`.
final Curriculum keyFluencyCurriculum = Curriculum(
  id: 'KEY_FLUENCY_24',
  version: '2',
  requirements: [
    for (final material in [
      for (final scale in allScales)
        if (coreForms.contains(scale.form)) scale,
      ...allRootPositionArpeggios,
    ])
      _requirement(material, HandConfiguration.together, octaves: 2),
  ],
);

CurriculumRequirement _requirement(
  TechnicalMaterial material,
  HandConfiguration hands, {
  required int octaves,
}) => CurriculumRequirement(
  id: '${material.materialId}:${hands.id}:$octaves',
  familyId: material.familyId,
  materialId: material.materialId,
  constraints: ExerciseConstraints(
    hands: hands,
    octaves: octaves,
    direction: ExerciseDirection.upDown,
  ),
  retrieval: CoverageRetrieval.unguided,
);
