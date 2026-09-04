import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'practice_focus.dart';
import 'practice_providers.dart';

/// What the learner is working toward.
///
/// One goal so far, and it is still offered as a choice rather than shown as a
/// fact. A goal is something a learner picks, and a row that only ever reads
/// back teaches them it is not.
Future<void> showGoalSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => const _GoalSheet(),
);

class _GoalSheet extends ConsumerWidget {
  const _GoalSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final catalog = ref.watch(practiceCatalogProvider);
    final plan = ref.watch(practicePlanProvider).value ?? PracticePlan.normal;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: layout.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Goal', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'The material KeyRecall works from. Everything it decides '
                    'to practice comes from inside your goal.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: layout.gutter),
              title: Text(goalName(plan.goalId)),
              subtitle: Text(goalDescription(catalog)),
              trailing: const Icon(Icons.check),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a goal is called where a learner reads it.
String goalName(String goalId) => switch (goalId) {
  'GENERAL_FLUENCY' => 'General piano technique',
  _ => goalId,
};

/// What the goal covers, in terms of what the catalog actually holds.
String goalDescription(List<TechnicalMaterial> catalog) {
  final families = familyIdsIn(catalog)
      .map(familyName)
      .map((name) => name.toLowerCase());
  return switch (families.length) {
    0 => 'Nothing is installed to practice.',
    1 => 'Every one of the ${families.single} KeyRecall supports.',
    _ =>
      'Every one of the '
          '${families.take(families.length - 1).join(', ')} and '
          '${families.last} KeyRecall supports.',
  };
}
