import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'practice_focus.dart';
import 'practice_providers.dart';

/// What this learner is working toward, and how much of it they have covered.
///
/// A goal is durable and rarely touched, so it lives behind the menu with the
/// other things that are true between sittings. Focus is not here: it is
/// temporary intent, it has its own control on the practice screen, and one
/// page holding both taught that they were the same kind of thing.
///
/// The choice is made on this page rather than in a sheet it opens. One goal
/// exists and it is still offered as a list with the current one marked, since
/// a goal is something a learner picks and a row that only ever reads back
/// teaches them it is not.
class GoalScreen extends ConsumerWidget {
  const GoalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final catalog = ref.watch(practiceCatalogProvider);
    final plan = ref.watch(practicePlanProvider).value ?? PracticePlan.normal;
    final coverage = ref.watch(practiceLoopProvider).value?.coverage;

    return Scaffold(
      appBar: AppBar(title: const Text('Goal')),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 16),
        children: [
          Text(
            'The material KeyRecall works from. Everything it decides to '
            'practice comes from inside your goal.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final goalId in offeredGoalIds)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(goalName(goalId)),
              subtitle: Text(goalDescription(catalog)),
              trailing: goalId == plan.goalId ? const Icon(Icons.check) : null,
              onTap: () => ref
                  .read(practicePlanProvider.notifier)
                  .apply(PracticePlan(goalId: goalId, focus: plan.focus)),
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

/// The goals this build can practice, in the order they are offered.
const List<String> offeredGoalIds = ['GENERAL_FLUENCY'];

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
