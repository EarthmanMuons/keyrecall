import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:material_ui/material_ui.dart';

/// How a placement tier is put to somebody who has not been assessed.
///
/// Described by what a learner can already do rather than by a label they have
/// to award themselves. "Intermediate" asks for a judgment about a word; "I
/// can play familiar scales from memory" asks about a morning at the piano.
/// The three progress across breadth, retrieval, fluency and coordination,
/// which is what the prior is summarizing.
///
/// The enum keeps its own names. What a tier is called in the model and how it
/// is put to a person are different problems.
extension PlacementTierCopy on PlacementTier {
  String get headline => switch (this) {
    PlacementTier.beginner => 'New to scales',
    PlacementTier.someExperience => 'Some experience',
    PlacementTier.advanced => 'Comfortable with scales',
  };

  String get detail => switch (this) {
    PlacementTier.beginner => 'I may need help with the notes or fingering.',
    PlacementTier.someExperience =>
      'I can play familiar scales from memory, but I’m still building '
          'fluency.',
    PlacementTier.advanced =>
      'I can play many scales from memory, hands together at a steady tempo.',
  };

  /// The short form, for a list that has room for a few words.
  String get label => switch (this) {
    PlacementTier.beginner => 'new to scales',
    PlacementTier.someExperience => 'some scales',
    PlacementTier.advanced => 'scales familiar',
  };
}

/// What the placement question says, wherever it is asked.
const placementQuestion = 'Where should we start?';

/// How exactly the answer has to fit.
///
/// The screen has already said that practice adapts to playing. What is left
/// to say is how much care the choice deserves, which is little.
const placementReassurance =
    'Pick the closest match. It doesn’t have to be exact.';

/// The three answers, with the chosen one marked.
///
/// Asked once per profile and never again. Placement is the prior the whole
/// history is computed from, so there is no edit control for it anywhere: a
/// later answer would reinterpret every attempt already recorded rather than
/// update a skill level, and erasing the history is the honest route to a
/// different start.
///
/// Selecting is separate from confirming, so a card is a choice rather than a
/// door out of the screen. Nothing is preselected: a prefilled answer to a
/// permanent question is one somebody confirms without reading.
class PlacementChoices extends StatelessWidget {
  const PlacementChoices({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The tier chosen so far, if any.
  final PlacementTier? selected;

  /// Takes a tier as it is picked.
  final void Function(PlacementTier) onSelected;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final tier in PlacementTier.values) ...[
        _PlacementChoice(
          tier: tier,
          isSelected: tier == selected,
          onSelected: () => onSelected(tier),
        ),
        if (tier != PlacementTier.values.last) const SizedBox(height: 8),
      ],
    ],
  );
}

/// One answer to the placement question.
class _PlacementChoice extends StatelessWidget {
  const _PlacementChoice({
    required this.tier,
    required this.isSelected,
    required this.onSelected,
  });

  final PlacementTier tier;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      selected: isSelected,
      child: Material(
        color: isSelected ? scheme.surfaceContainerHigh : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tier.headline, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        tier.detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks where to start, or null when nobody answered.
///
/// The dialog form, for adding a profile beside the ones that already exist.
Future<PlacementTier?> askForPlacement(BuildContext context) =>
    showDialog<PlacementTier>(
      context: context,
      builder: (context) => const _PlacementDialog(),
    );

class _PlacementDialog extends StatefulWidget {
  const _PlacementDialog();

  @override
  State<_PlacementDialog> createState() => _PlacementDialogState();
}

class _PlacementDialogState extends State<_PlacementDialog> {
  PlacementTier? _selected;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(placementQuestion),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            placementReassurance,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          PlacementChoices(
            selected: _selected,
            onSelected: (tier) => setState(() => _selected = tier),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _selected == null
            ? null
            : () => Navigator.of(context).pop(_selected),
        child: const Text('Continue'),
      ),
    ],
  );
}
