import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'goal_sheet.dart';
import 'practice_providers.dart';

/// What this learner is working toward, and how much of it they have covered.
///
/// A goal is durable and rarely touched, so it lives behind the menu with the
/// other things that are true between sittings. Focus is not here: it is
/// temporary intent, it has its own control on the practice screen, and one
/// page holding both taught that they were the same kind of thing.
class GoalScreen extends ConsumerWidget {
  const GoalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final catalog = ref.watch(practiceCatalogProvider);
    final goalId = ref.watch(practicePlanProvider).value?.goalId ?? '';
    final coverage = ref.watch(practiceLoopProvider).value?.coverage;

    return Scaffold(
      appBar: AppBar(title: const Text('Goal')),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 8),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(goalName(goalId), style: theme.textTheme.titleMedium),
            subtitle: Text(goalDescription(catalog)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showGoalSheet(context),
          ),
          if (coverage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${coverage.coveredTargets} of ${coverage.targetCount} '
                'covered so far',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
