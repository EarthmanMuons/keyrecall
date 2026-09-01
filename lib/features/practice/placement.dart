import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:material_ui/material_ui.dart';

import '../../wordmark.dart';
import 'attempt_screen.dart';
import 'practice_providers.dart';

/// How a placement tier is put to somebody who has not been assessed.
///
/// Described by what a learner can already do rather than by a label they have
/// to award themselves. "Intermediate" asks for a judgment about a word; "I
/// can usually play a familiar scale with one hand without looking" asks about
/// a morning at the piano. The three progress across breadth, retrieval,
/// execution and coordination, which is what the prior is summarizing.
///
/// The enum keeps its own names. What a tier is called in the model and how it
/// is put to a person are different problems.
extension PlacementTierCopy on PlacementTier {
  String get headline => switch (this) {
    PlacementTier.beginner => 'I’m new to scales.',
    PlacementTier.someExperience => 'I’ve practiced some scales.',
    PlacementTier.advanced => 'Scales are already familiar.',
  };

  String get detail => switch (this) {
    PlacementTier.beginner => 'I may need help with the notes or fingering.',
    PlacementTier.someExperience =>
      'I can usually play a familiar scale with one hand without looking at '
          'the notes.',
    PlacementTier.advanced =>
      'I can play several scales from memory, with both hands and at a steady '
          'tempo.',
  };

  /// The short form, for a list that has room for a few words.
  String get label => switch (this) {
    PlacementTier.beginner => 'new to scales',
    PlacementTier.someExperience => 'some scales',
    PlacementTier.advanced => 'scales familiar',
  };
}

/// What the placement question says, wherever it is asked.
///
/// Asked once per profile and never again. Placement is the prior the whole
/// history is computed from, so there is no edit control for it anywhere: a
/// later answer would reinterpret every attempt already recorded rather than
/// update a skill level, and erasing the history is the honest route to a
/// different start.
///
/// Nothing is preselected. A prefilled answer to a permanent question is one
/// somebody confirms without reading.
class PlacementQuestion extends StatelessWidget {
  const PlacementQuestion({required this.onChosen, super.key});

  /// Takes the answer.
  final void Function(PlacementTier) onChosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This only sets your starting point. KeyRecall will adjust from how '
          'you play.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final tier in PlacementTier.values) ...[
          _PlacementChoice(tier: tier, onChosen: () => onChosen(tier)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// One answer to the placement question.
class _PlacementChoice extends StatelessWidget {
  const _PlacementChoice({required this.tier, required this.onChosen});

  final PlacementTier tier;
  final VoidCallback onChosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onChosen,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tier.headline, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            tier.detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
      builder: (context) => AlertDialog(
        title: const Text('Where should we start?'),
        content: SingleChildScrollView(
          child: PlacementQuestion(
            onChosen: (tier) => Navigator.of(context).pop(tier),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

/// The placement question as the whole screen, for an install with nobody on
/// it yet.
///
/// The first launch has one decision and it is this one, because it is the one
/// that cannot be made later: placement is the prior every attempt is
/// interpreted against, and by the time somebody has practised enough to know
/// their own answer, changing it would mean discarding the practice. There is
/// no name prompt beside it. One person on one instrument is the ordinary
/// case, and a name is a thing the profile screen can ask for if a second
/// person ever appears.
class PlacementScreen extends ConsumerWidget {
  const PlacementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wordmark(style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Where should we start?',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  PlacementQuestion(
                    onChosen: (tier) =>
                        ref.read(profileRosterProvider.notifier).place(tier),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The practice app, behind the one question a first launch has to ask.
///
/// The gate is whether this install has anybody on it, read from the roster
/// rather than from a flag: an install with a profile has been placed, and one
/// without has not. It sits above everything that reads the practice loop
/// because opening a sitting conjures a default profile when none exists, and
/// a profile conjured before the question is answered is one placed at a tier
/// nobody chose and nobody can change.
///
/// A roster that cannot be read falls through to the app, which has its own
/// account of unreadable storage and the ways out of it.
class PlacementGate extends ConsumerWidget {
  const PlacementGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(profileRosterProvider)) {
        AsyncData(:final value) when value.isEmpty => const PlacementScreen(),
        AsyncData() || AsyncError() => const AttemptScreen(),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
      };
}
