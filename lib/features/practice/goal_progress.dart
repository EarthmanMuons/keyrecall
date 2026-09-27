import 'package:flutter/foundation.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

/// One goal's targets, arranged the way the goal is shaped.
///
/// Read from coverage and nothing else, so it counts what the goal asks for
/// and never the route to it: a one-octave warm-up or a cued attempt is not a
/// target and cannot move this. Once a target is covered it stays covered.
@immutable
class GoalProgress {
  final List<GoalProgressSection> sections;

  GoalProgress(Iterable<GoalProgressSection> sections)
    : sections = List.unmodifiable(sections);

  int get covered => sections.fold(0, (sum, section) => sum + section.covered);
  int get total => sections.fold(0, (sum, section) => sum + section.total);
}

/// The targets of one material family.
@immutable
class GoalProgressSection {
  final String familyId;
  final List<GoalProgressRow> rows;

  GoalProgressSection({
    required this.familyId,
    required Iterable<GoalProgressRow> rows,
  }) : rows = List.unmodifiable(rows);

  int get covered => rows.fold(0, (sum, row) => sum + row.covered);
  int get total => rows.fold(0, (sum, row) => sum + row.cells.length);
}

/// One material's targets, a cell per hand configuration the goal asks for.
@immutable
class GoalProgressRow {
  final TechnicalMaterial material;
  final List<GoalProgressCell> cells;

  GoalProgressRow({
    required this.material,
    required Iterable<GoalProgressCell> cells,
  }) : cells = List.unmodifiable(cells);

  int get covered => cells.where((cell) => cell.covered).length;
  bool get isComplete => covered == cells.length;
}

@immutable
class GoalProgressCell {
  /// The shape the target asks for.
  final ExerciseConstraints constraints;
  final bool covered;

  const GoalProgressCell({required this.constraints, required this.covered});

  /// The hands the target asks for, or null for a target that names none.
  HandConfiguration? get hands => constraints.hands;
}

/// How a section can be drawn without leaving any target unnamed.
enum GoalProgressLayout {
  /// One target per material: the material names it.
  keyGrid,

  /// Several per material, told apart by their hands alone.
  handRows,

  /// Anything else: each target named by its whole shape.
  targetList,
}

/// The most compact layout that still says what each of [section]'s targets
/// is.
///
/// A hand mark is only a name while no two targets of a material share one.
/// A curriculum asking the same scale of one hand at two spans would otherwise
/// show two marks with one label and no way to tell which was which.
GoalProgressLayout layoutOf(GoalProgressSection section) {
  if (section.rows.every((row) => row.cells.length == 1)) {
    return GoalProgressLayout.keyGrid;
  }
  final handsTellApart = section.rows.every((row) {
    final hands = [for (final cell in row.cells) cell.hands];
    return !hands.contains(null) && hands.toSet().length == hands.length;
  });
  return handsTellApart
      ? GoalProgressLayout.handRows
      : GoalProgressLayout.targetList;
}

/// [scope]'s targets under [coverage], in the order the curriculum lists them.
///
/// Families appear in the order their first target does, materials likewise,
/// and a material's cells in hand order, right before left before together.
GoalProgress goalProgressOf(
  ResolvedPracticeScope scope,
  ScopeCoverage coverage,
) {
  final cells = <String, Map<TechnicalMaterial, List<GoalProgressCell>>>{};
  for (final requirement in scope.requirements) {
    if (!requirement.isTarget) continue;
    cells
        .putIfAbsent(requirement.material.familyId, () => {})
        .putIfAbsent(requirement.material, () => [])
        .add(
          GoalProgressCell(
            constraints: requirement.requirement.constraints,
            covered: coverage.coveredTargetIds.contains(
              requirement.requirement.id,
            ),
          ),
        );
  }
  int handOrder(GoalProgressCell cell) =>
      cell.hands?.index ?? HandConfiguration.values.length;
  return GoalProgress([
    for (final MapEntry(key: familyId, value: materials) in cells.entries)
      GoalProgressSection(
        familyId: familyId,
        rows: [
          for (final MapEntry(key: material, value: materialCells)
              in materials.entries)
            GoalProgressRow(
              material: material,
              cells: [...materialCells]
                ..sort((a, b) => handOrder(a).compareTo(handOrder(b))),
            ),
        ],
      ),
  ]);
}
