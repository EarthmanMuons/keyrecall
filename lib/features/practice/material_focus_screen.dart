import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'exercise_presentation.dart';
import 'practice_focus.dart';
import 'practice_providers.dart';

/// Choosing material by its characteristics rather than from a list.
///
/// Facets rather than a tree, because hand configuration, motion, and span cut
/// across the families and forms and would each need the tree rebuilt around
/// them. Nothing here is a route the scheduler takes: the selection says what
/// may be drawn from, and what to practice next remains KeyRecall's question.
///
/// The two ways to use a selection are kept apart on the way out. Practicing
/// only the selection is what choosing material reads as, so it leads;
/// emphasizing it leaves everything else in the goal eligible and is offered
/// under it for the learner who means that instead.
class MaterialFocusScreen extends ConsumerStatefulWidget {
  const MaterialFocusScreen({super.key});

  @override
  ConsumerState<MaterialFocusScreen> createState() =>
      _MaterialFocusScreenState();
}

class _MaterialFocusScreenState extends ConsumerState<MaterialFocusScreen> {
  final Set<String> _familyIds = {};
  final Set<ScaleForm> _forms = {};
  final Set<String> _tonics = {};

  /// Seeded from the focus in force, so opening this from an active focus
  /// starts where that focus left off rather than at nothing selected.
  bool _seeded = false;

  MaterialFocus get _selection => MaterialFocus(
    familyIds: _familyIds,
    scaleFormIds: {for (final form in _forms) form.id},
    arpeggioQualityIds: {
      for (final form in _forms) arpeggioQualityFor(form).id,
    },
    tonics: _tonics,
  );

  void _toggle<T>(Set<T> facet, T value, {required bool selected}) =>
      setState(() => selected ? facet.add(value) : facet.remove(value));

  Future<void> _apply(FocusStrength strength, String label) async {
    await ref
        .read(practicePlanProvider.notifier)
        .apply(
          (ref.read(practicePlanProvider).value ?? PracticePlan.normal)
              .focusedOn(
                ActiveFocus(
                  label: label,
                  strength: strength,
                  material: _selection,
                ),
              ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final catalog = ref.watch(practiceCatalogProvider);
    final held = ref.watch(practicePlanProvider).value?.focus?.material;
    if (!_seeded && held != null) {
      _seeded = true;
      _familyIds.addAll(held.familyIds);
      _forms.addAll(formsOf(held));
      _tonics.addAll(held.tonics);
    }

    final families = familyIdsIn(catalog);
    final forms = formsIn(catalog);
    final selection = _selection.selectionOf(catalog);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose material')),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 16),
        children: [
          if (families.length > 1)
            _Facet(
              title: 'Type',
              children: [
                for (final familyId in families)
                  _Option(
                    label: familyName(familyId),
                    selected: _familyIds.contains(familyId),
                    onSelected: (selected) =>
                        _toggle(_familyIds, familyId, selected: selected),
                  ),
              ],
            ),
          if (forms.isNotEmpty)
            _Facet(
              title: 'Form',
              children: [
                for (final form in forms)
                  _Option(
                    label: formName(form),
                    selected: _forms.contains(form),
                    onSelected: (selected) =>
                        _toggle(_forms, form, selected: selected),
                  ),
              ],
            ),
          _Facet(
            title: 'Keys',
            children: [
              for (final tonic in tonicsIn(catalog))
                _Option(
                  label: prettyTonic(tonic),
                  selected: _tonics.contains(tonic),
                  onSelected: (selected) =>
                      _toggle(_tonics, tonic, selected: selected),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _Actions(
        selection: selection,
        onExclude: selection.isEmpty
            ? null
            : () => _apply(FocusStrength.exclusive, selectionLabel(selection)),
        onEmphasize: selection.isEmpty
            ? null
            : () => _apply(FocusStrength.emphasis, selectionLabel(selection)),
      ),
    );
  }
}

/// What one action does, under the action itself.
class _Explanation extends StatelessWidget {
  const _Explanation(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// One row of choices, none of which is required.
class _Facet extends StatelessWidget {
  const _Facet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 1.2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: onSelected,
  );
}

/// What the selection comes to, and the two things it can be used for.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.selection,
    required this.onExclude,
    required this.onEmphasize,
  });

  final List<TechnicalMaterial> selection;
  final VoidCallback? onExclude;
  final VoidCallback? onEmphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              selection.isEmpty
                  ? 'Nothing selected yet'
                  : '${selectionLabel(selection)} selected',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Each action says what it does under itself. The difference
            // between emphasizing and excluding is the whole decision here,
            // and a paragraph under both of them asks somebody to hold two
            // buttons in their head while they read it.
            FilledButton(
              onPressed: onExclude,
              child: const Text('Practice only these'),
            ),
            const SizedBox(height: 6),
            _Explanation('Temporarily exclude everything else.'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onEmphasize,
              child: const Text('Focus on these'),
            ),
            const SizedBox(height: 6),
            _Explanation(
              'Emphasize these while keeping other useful material in the mix.',
            ),
          ],
        ),
      ),
    );
  }
}
