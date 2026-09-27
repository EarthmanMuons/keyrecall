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
/// or nothing has reported coverage yet.
///
/// General technique has no finish line, so it has no progress here; the
/// fluency report is what describes open-ended practice.
final goalProgressProvider = Provider<GoalProgress?>((ref) {
  final plan = ref.watch(practicePlanProvider).value;
  final coverage = ref.watch(practiceLoopProvider).value?.coverage;
  if (plan == null || coverage == null || !hasFinishLine(plan)) return null;
  final catalog = ref.watch(practiceCatalogProvider);
  if (plan.resolve(catalog) case ResolvedPlan(:final goal, :final focus)) {
    if (PracticeScopeResolver().resolve(
          goal: goal,
          focus: focus,
          catalog: catalog,
          instrument: InstrumentProfile(),
        )
        case ValidPracticeScope(:final scope)) {
      return goalProgressOf(scope, coverage);
    }
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
    final plan = ref.watch(practicePlanProvider).value ?? PracticePlan.normal;
    final progress = ref.watch(goalProgressProvider);

    return Scaffold(
      appBar: AppBar(title: Text(goalName(plan.goalId))),
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
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress.total == 0
                      ? 0
                      : progress.covered / progress.total,
                ),
                const SizedBox(height: 8),
                Text(
                  'Something counts once you have played it from memory the '
                  'way the goal asks. Practice keeps coming back to it, and '
                  'that never takes it away.',
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
                  if (section.rows.every((row) => row.cells.length == 1))
                    _KeyGrid(section)
                  else
                    for (final row in section.rows) _HandsRow(row),
                ],
              ],
            ),
    );
  }
}

/// What a section is called: the family's plural.
String sectionName(GoalProgressSection section) =>
    section.familyId == TechnicalMaterial.arpeggioFamilyId
    ? 'Arpeggios'
    : 'Scales';

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
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done ? scheme.primaryContainer : null,
          border: Border.all(
            color: done ? scheme.primaryContainer : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          keyLabel(row.material),
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

/// A hand configuration in the room a row's mark has.
String handsMark(HandConfiguration? hands) => switch (hands) {
  HandConfiguration.right => 'RH',
  HandConfiguration.left => 'LH',
  HandConfiguration.together => 'HT',
  null => '',
};
