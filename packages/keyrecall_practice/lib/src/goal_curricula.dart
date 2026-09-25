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

/// Every major and natural-minor key, hands together over two octaves, up and
/// down, from memory.
///
/// Scales only in this version. The root-position arpeggios join once they
/// are generated up and down, as a new version, rather than as ascending-only
/// requirements that would say less than the goal's name does. The altered
/// minor forms are extensions of these tonalities and not part of having them.
final Curriculum keyFluencyCurriculum = Curriculum(
  id: 'KEY_FLUENCY_24',
  version: '1',
  requirements: [
    for (final material in allScales)
      if (coreForms.contains(material.form))
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
