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
/// V1 runs one goal, general fluency over the whole catalog. A scoped goal is
/// expressible so analysis can construct one, and `PracticeSession.open`
/// refuses to run it: scoping the catalog reaches a slot that admits nothing,
/// which `docs/design/future-planning.md` section 4.9 records.
@immutable
class PracticeGoal {
  /// What this goal is called.
  final String id;

  /// The material this goal is working toward, or null for all of it.
  final Set<String>? targetMaterialIds;

  factory PracticeGoal({required String id, Set<String>? targetMaterialIds}) =>
      PracticeGoal._(
        id: id,
        targetMaterialIds: targetMaterialIds == null
            ? null
            : Set.unmodifiable(targetMaterialIds),
      );

  const PracticeGoal._({required this.id, this.targetMaterialIds});

  /// Everything the system supports: general scale fluency, no destination
  /// narrower than the catalog.
  static const PracticeGoal generalFluency = PracticeGoal._(
    id: 'GENERAL_FLUENCY',
  );

  /// Whether this goal names an explicit material scope.
  ///
  /// About the goal, not about any catalog it is applied to: a goal listing
  /// every material is scoped, and narrows nothing.
  bool get isScoped => targetMaterialIds != null;

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
