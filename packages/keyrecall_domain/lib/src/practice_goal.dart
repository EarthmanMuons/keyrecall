import 'package:meta/meta.dart';

import 'technical_material.dart';

/// What the learner is trying to learn.
///
/// The destination, not the route. A goal narrows the universe of material
/// under consideration; it does not say what to practice next, which is the
/// scheduler's question, and it does not say what a learner is ready for,
/// which is the `REQUIRES` gate's:
///
/// ```text
/// allScales -> goal scope -> material admission -> ranking
/// ```
///
/// Keeping those apart matters most for a goal that names a syllabus. Choosing
/// one should say "these are the destination materials", not make every one of
/// them admissible at once, and it should not stop the scheduler using easier
/// related material that prepares for them.
///
/// V1 has one goal, general fluency over the whole catalog.
@immutable
class PracticeGoal {
  /// What this goal is called.
  final String id;

  /// The material this goal is working toward, or null for all of it.
  final Set<String>? targetMaterialIds;

  const PracticeGoal({required this.id, this.targetMaterialIds});

  /// Everything the system supports: general scale fluency, no destination
  /// narrower than the catalog.
  static const PracticeGoal generalFluency = PracticeGoal(
    id: 'GENERAL_FLUENCY',
  );

  /// Whether [material] is in scope.
  bool includes(TechnicalMaterial material) =>
      targetMaterialIds?.contains(material.materialId) ?? true;

  /// The materials from [catalog] this goal is working toward.
  List<TechnicalMaterial> scopeOf(List<TechnicalMaterial> catalog) => [
    for (final material in catalog)
      if (includes(material)) material,
  ];

  @override
  String toString() => 'PracticeGoal($id)';
}
