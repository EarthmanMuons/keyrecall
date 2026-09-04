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
/// The two ways to use a selection are kept apart on the way out. Emphasizing
/// it leaves everything else in the goal eligible; practicing only it does not,
/// and a learner who has come this far is the one person who wants to be asked
/// which they mean.
class MaterialFocusScreen extends ConsumerStatefulWidget {
  const MaterialFocusScreen({super.key});

  @override
  ConsumerState<MaterialFocusScreen> createState() =>
      _MaterialFocusScreenState();
}

class _MaterialFocusScreenState extends ConsumerState<MaterialFocusScreen> {
  final Set<String> _familyIds = {};
  final Set<String> _scaleFormIds = {};
  final Set<String> _arpeggioQualityIds = {};
  final Set<String> _tonics = {};

  /// Seeded from the focus in force, so opening this from an active focus
  /// starts where that focus left off rather than at nothing selected.
  bool _seeded = false;

  MaterialFocus get _selection => MaterialFocus(
    familyIds: _familyIds,
    scaleFormIds: _scaleFormIds,
    arpeggioQualityIds: _arpeggioQualityIds,
    tonics: _tonics,
  );

  void _toggle(Set<String> facet, String value, {required bool selected}) =>
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
      _scaleFormIds.addAll(held.scaleFormIds);
      _arpeggioQualityIds.addAll(held.arpeggioQualityIds);
      _tonics.addAll(held.tonics);
    }

    final families = familyIdsIn(catalog);
    final forms = scaleFormsIn(catalog);
    final qualities = arpeggioQualitiesIn(catalog);
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
              title: 'Scale form',
              children: [
                for (final form in forms)
                  _Option(
                    label: scaleFormName(form),
                    selected: _scaleFormIds.contains(form.id),
                    onSelected: (selected) =>
                        _toggle(_scaleFormIds, form.id, selected: selected),
                  ),
              ],
            ),
          if (qualities.isNotEmpty)
            _Facet(
              title: 'Chord quality',
              children: [
                for (final quality in qualities)
                  _Option(
                    label: arpeggioQualityName(quality),
                    selected: _arpeggioQualityIds.contains(quality.id),
                    onSelected: (selected) => _toggle(
                      _arpeggioQualityIds,
                      quality.id,
                      selected: selected,
                    ),
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
        onEmphasize: selection.isEmpty
            ? null
            : () => _apply(FocusStrength.emphasis, selectionLabel(selection)),
        onExclude: selection.isEmpty
            ? null
            : () => _apply(FocusStrength.exclusive, selectionLabel(selection)),
      ),
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
    required this.onEmphasize,
    required this.onExclude,
  });

  final List<TechnicalMaterial> selection;
  final VoidCallback? onEmphasize;
  final VoidCallback? onExclude;

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
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onEmphasize,
              child: const Text('Focus on these'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onExclude,
              child: const Text('Practice only these'),
            ),
            const SizedBox(height: 4),
            Text(
              'Focusing keeps other useful practice in the mix. Practicing '
              'only these leaves everything else out until you change it back.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
