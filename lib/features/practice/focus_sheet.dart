import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'material_focus_screen.dart';
import 'practice_focus.dart';
import 'practice_providers.dart';

/// Whether a focus is in force, and what it is called, for a screen reader.
///
/// The control is an icon, so the state it carries has to be said somewhere.
String focusButtonLabel(PracticePlan plan) => switch (plan.focus) {
  null => 'Practice focus. None set.',
  final focus when focus.isExclusive => 'Practice focus. Only ${focus.label}.',
  final focus => 'Practice focus. ${focus.label}.',
};

/// What KeyRecall should draw from for now.
///
/// Practicing normally is first and is the ordinary answer. The named focuses
/// under it come from the material the active goal actually contains, so this
/// list is not a taxonomy somebody has to learn: it is what there is to ask
/// for. Anything more particular is a screen away rather than on this one.
Future<void> showFocusSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => const _FocusSheet(),
);

class _FocusSheet extends ConsumerWidget {
  const _FocusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final catalog = ref.watch(practiceCatalogProvider);
    final plan = ref.watch(practicePlanProvider).value;
    final focus = plan?.focus;
    final suggestions = focusSuggestionsFor(catalog);

    Future<void> apply(ActiveFocus? chosen) async {
      final notifier = ref.read(practicePlanProvider.notifier);
      final current = plan ?? PracticePlan.normal;
      await notifier.apply(
        chosen == null
            ? current.practicingNormally()
            : current.focusedOn(chosen),
      );
      if (context.mounted) Navigator.of(context).pop();
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, 0, 0, layout.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Practice focus', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'KeyRecall emphasizes what you ask for and keeps including '
                    'other useful practice.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Choice(
              label: 'Practice normally',
              selected: focus == null,
              onTap: () => apply(null),
            ),
            for (final suggestion in suggestions)
              _Choice(
                label: suggestion.label,
                selected:
                    focus != null &&
                    !focus.isExclusive &&
                    focus.material == suggestion.material,
                onTap: () => apply(suggestion.asEmphasis()),
              ),
            if (focus != null &&
                !suggestions.any(
                  (suggestion) => suggestion.material == focus.material,
                ))
              _Choice(
                label: focus.label,
                selected: true,
                onTap: () => apply(focus),
              ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Choose specific material'),
              contentPadding: EdgeInsets.symmetric(horizontal: layout.gutter),
              // The navigator is taken before the sheet closes: this context
              // goes with it, and the screen is pushed onto the route the
              // sheet was over.
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (context) => const MaterialFocusScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One focus to pick, marked when it is the one in force.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: layout.gutter),
      title: Text(label),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}
