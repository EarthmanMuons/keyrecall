import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'focus_sheet.dart';
import 'goal_sheet.dart';
import 'practice_providers.dart';

/// The two things a learner controls about what they are asked to play.
///
/// Not settings. A goal is the material everything is chosen from and is meant
/// to be left alone; a focus is temporary intent that should be easy to see and
/// easy to drop. Naming both on one screen is what says which is which.
class PracticePlanScreen extends ConsumerWidget {
  const PracticePlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final catalog = ref.watch(practiceCatalogProvider);
    final plan = ref.watch(practicePlanProvider).value ?? PracticePlan.normal;
    final coverage = ref.watch(practiceLoopProvider).value?.coverage;

    return Scaffold(
      appBar: AppBar(title: const Text('Goals & focus')),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 8),
        children: [
          const _Heading('Goal'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              goalName(plan.goalId),
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(goalDescription(catalog)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showGoalSheet(context),
          ),
          if (coverage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                '${coverage.coveredTargets} of ${coverage.targetCount} '
                'covered so far',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const Divider(height: 32),
          const _Heading('Focus'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(focusName(plan), style: theme.textTheme.titleMedium),
            subtitle: Text(focusExplanation(plan)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showFocusSheet(context),
          ),
          if (plan.isFocused)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    ref.read(practicePlanProvider.notifier).practiceNormally(),
                child: const Text('Practice normally again'),
              ),
            ),
        ],
      ),
    );
  }
}

/// The focus in force, as a learner would say it.
String focusName(PracticePlan plan) => switch (plan.focus) {
  null => 'Practicing normally',
  final focus when focus.isExclusive => 'Only ${focus.label.toLowerCase()}',
  final focus => focus.label,
};

/// What the focus in force means for what comes next.
String focusExplanation(PracticePlan plan) => switch (plan.focus) {
  null => 'KeyRecall chooses from everything in your goal.',
  final focus when focus.isExclusive =>
    'Nothing outside this selection is offered until you change it back.',
  _ => 'Emphasized, with other useful practice still in the mix.',
};

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        letterSpacing: 1.2,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
