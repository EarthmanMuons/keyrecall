import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'focus_sheet.dart';
import 'practice_plan_screen.dart' show focusName;
import 'practice_providers.dart';

/// What this sitting is drawing from, over the exercise it produced.
///
/// One line while nothing is focused, because the ordinary state of the app is
/// that a learner can just practice. A focus is exceptional intent and reads
/// like one: it is named where the next exercise is, so somebody returning
/// three days later is told why they keep being asked for minor material
/// instead of having to work it out.
///
/// Gone while an attempt is under way. Nothing on it is usable with both hands
/// on the keys.
class FocusBar extends ConsumerWidget {
  const FocusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final plan = ref.watch(practicePlanProvider).value ?? PracticePlan.normal;
    final focused = plan.isFocused;

    return Material(
      color: focused
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.surface,
      child: InkWell(
        onTap: () => showFocusSheet(context),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 8),
          child: Row(
            children: [
              Icon(
                focused ? Icons.filter_alt : Icons.auto_mode,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  focusName(plan),
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // The same word in both states. What is in force is what the
              // line says; the action beside it is the same action either way.
              Text(
                'Change',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
