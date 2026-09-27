import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'exercise_presentation.dart';
import 'goal_progress.dart';
import 'goal_screen.dart';
import 'practice_providers.dart';

/// Progress toward the goal in force, or null where there is no finish line
/// or no sitting is open.
///
/// Read from the goal's targets and the history alone. It does not wait on a
/// scheduling decision, so it is there while an attempt is pending or under
/// review, and it never generates the candidates a decision would.
///
/// General technique has no finish line, so it has no progress here; the
/// fluency report is what describes open-ended practice.
final goalProgressProvider = Provider<GoalProgress?>((ref) {
  final loop = ref.watch(practiceLoopProvider).value;
  if (loop == null || !hasFinishLine(loop.plan)) return null;
  final catalog = ref.watch(practiceCatalogProvider);
  if (loop.plan.resolve(catalog) case ResolvedPlan(:final goal, :final focus)) {
    final targets = PracticeScopeResolver().targetsOf(
      goal: goal,
      focus: focus,
      catalog: catalog,
    );
    if (targets.isEmpty) return null;
    return goalProgressOf(
      targets,
      coverageOf(targets, loop.session.journal.records),
    );
  }
  return null;
});

/// What the goal asks for, and which of it has been demonstrated.
///
/// Laid out the way the goal is shaped: a row per material with a mark per
/// hand where the goal asks for each hand, and a compact grid of keys where it
/// asks for one thing of each.
class GoalProgressScreen extends ConsumerWidget {
  const GoalProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final plan =
        ref.watch(practiceLoopProvider).value?.plan ?? PracticePlan.normal;
    final progress = ref.watch(goalProgressProvider);
    final focused = plan.focus?.isExclusive ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(focused ? 'Focus progress' : goalName(plan.goalId)),
      ),
      body: progress == null
          ? const Center(child: Text('Nothing to show yet.'))
          : ListView(
              padding: EdgeInsets.symmetric(
                horizontal: layout.gutter,
                vertical: 16,
              ),
              children: [
                Text(
                  '${progress.covered} of ${progress.total} demonstrated',
                  style: theme.textTheme.titleLarge,
                ),
                if (focused)
                  Text(
                    'In this focus, within ${goalName(plan.goalId)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress.total == 0
                      ? 0
                      : progress.covered / progress.total,
                ),
                const SizedBox(height: 8),
                Text(
                  progressExplanation(progress),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final section in progress.sections) ...[
                  const SizedBox(height: 24),
                  Text(
                    '${sectionName(section)}: ${section.covered} of '
                    '${section.total}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  GoalProgressSectionView(section),
                ],
              ],
            ),
    );
  }
}

/// What it takes for something to count, in the terms its targets use.
///
/// From memory only where every target asks for that. A general technique
/// focus counts playing that follows a preview, and saying "from memory" there
/// would hold the learner to a standard the count does not.
String progressExplanation(GoalProgress progress) =>
    '${progress.fromMemory ? 'Something counts once you have played it from '
              'memory the way the goal asks.' : 'Something counts once you '
              'have played it the way the goal asks, recalling it yourself '
              'rather than following cues.'} '
    'Practice keeps coming back to it, and that never takes it away.';

/// What a section is called: the family's plural, or its id for a family
/// this build has no name for.
String sectionName(GoalProgressSection section) => switch (section.familyId) {
  TechnicalMaterial.scaleFamilyId => 'Scales',
  TechnicalMaterial.arpeggioFamilyId => 'Arpeggios',
  final familyId => familyId,
};

/// The whole shape a target asks for, as a learner would say it.
///
/// What the explicit list names each target by, so two targets of one
/// material read differently whenever they are different.
String targetShapeName(ExerciseConstraints constraints) => [
  if (constraints.hands case final hands?) handsName(hands),
  if (constraints.octaves case final octaves?) octavesName(octaves),
  if (constraints.handMotion == HandMotion.contrary) 'contrary motion',
  switch (constraints.direction) {
    ExerciseDirection.up => 'up',
    ExerciseDirection.upDown => 'up and down',
    null => null,
  },
  if (constraints.minimumTempoBpm case final tempo?) 'at ${tempo.round()} bpm',
].nonNulls.join(', ');

/// A material as one key on a grid: the tonic, with `m` for minor.
///
/// Only for materials a grid can name that shortly. Anything else is written
/// out in full, since an altered form reduced to its tonic reads as the major.
String keyLabel(TechnicalMaterial material) => switch (material) {
  ScaleMaterial(:final tonic, form: ScaleForm.major) ||
  ArpeggioMaterial(
    :final tonic,
    quality: ArpeggioQuality.major,
  ) => prettyTonic(tonic),
  ScaleMaterial(:final tonic, form: ScaleForm.naturalMinor) ||
  ArpeggioMaterial(
    :final tonic,
    quality: ArpeggioQuality.minor,
  ) => '${prettyTonic(tonic)}m',
  _ => materialName(material),
};

/// Whether [material] sits among the minor keys of a grid.
bool isMinorKey(TechnicalMaterial material) => switch (material) {
  ScaleMaterial(:final form) => form != ScaleForm.major,
  ArpeggioMaterial(:final quality) => quality == ArpeggioQuality.minor,
};

/// One section of a goal's progress, in the layout that names its targets.
class GoalProgressSectionView extends StatelessWidget {
  const GoalProgressSectionView(this.section, {super.key});

  final GoalProgressSection section;

  @override
  Widget build(BuildContext context) => switch (layoutOf(section)) {
    GoalProgressLayout.keyGrid => _KeyGrid(section),
    GoalProgressLayout.handRows => Column(
      children: [for (final row in section.rows) _HandsRow(row)],
    ),
    GoalProgressLayout.targetList => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final row in section.rows) _TargetRows(row)],
    ),
  };
}

class _KeyGrid extends StatelessWidget {
  const _KeyGrid(this.section);

  final GoalProgressSection section;

  @override
  Widget build(BuildContext context) {
    final majors = [
      for (final row in section.rows)
        if (!isMinorKey(row.material)) row,
    ];
    final minors = [
      for (final row in section.rows)
        if (isMinorKey(row.material)) row,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rows in [majors, minors])
          if (rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final row in rows) _KeyMark(row)],
              ),
            ),
      ],
    );
  }
}

class _KeyMark extends StatelessWidget {
  const _KeyMark(this.row);

  final GoalProgressRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = row.isComplete;
    return Semantics(
      label:
          '${materialName(row.material)}, '
          '${done ? 'demonstrated' : 'not yet demonstrated'}',
      excludeSemantics: true,
      // Sized to its label, with a floor for touch and for one-letter keys.
      // An alignment here would stretch it to the width of the run instead.
      child: Container(
        constraints: const BoxConstraints(minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: done ? scheme.primaryContainer : null,
          border: Border.all(
            color: done ? scheme.primaryContainer : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          keyLabel(row.material),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: done ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _HandsRow extends StatelessWidget {
  const _HandsRow(this.row);

  final GoalProgressRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(materialName(row.material))),
          for (final cell in row.cells)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Semantics(
                label:
                    '${cell.hands == null ? 'This' : handsName(cell.hands!)}, '
                    '${cell.covered ? 'demonstrated' : 'not yet demonstrated'}',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cell.covered
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: cell.covered
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      handsMark(cell.hands),
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A material's targets one to a line, each named by its whole shape.
class _TargetRows extends StatelessWidget {
  const _TargetRows(this.row);

  final GoalProgressRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(materialName(row.material)),
          for (final cell in row.cells)
            Semantics(
              label:
                  '${targetShapeName(cell.constraints)}, '
                  '${cell.covered ? 'demonstrated' : 'not yet demonstrated'}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Row(
                  children: [
                    Icon(
                      cell.covered
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: cell.covered
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        targetShapeName(cell.constraints),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A hand configuration in the room a row's mark has.
String handsMark(HandConfiguration? hands) => switch (hands) {
  HandConfiguration.right => 'RH',
  HandConfiguration.left => 'LH',
  HandConfiguration.together => 'HT',
  null => '',
};
