import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'exercise_presentation.dart';

/// What each line of the task statement means, for the exercise on screen.
///
/// Written against this exercise rather than in general: somebody asking what
/// "Contrary motion" means is looking at those words, and a glossary of every
/// term the app can produce would make them find their own again.
Future<void> showTaskHelp(BuildContext context, Exercise exercise) =>
    showTermHelp(
      context,
      title: 'What you are practicing',
      entries: taskHelpEntries(exercise),
    );

Future<void> showTermHelp(
  BuildContext context, {
  required String title,
  required List<(String term, String meaning)> entries,
  String? introduction,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) =>
      _TermHelp(title: title, introduction: introduction, entries: entries),
);

/// What each term on the task statement means, in the order the statement
/// puts them.
///
/// The terms are produced by the same naming this app writes on the statement,
/// so the entry somebody is looking for reads exactly as the line they tapped.
List<(String term, String meaning)> taskHelpEntries(Exercise exercise) {
  final conditions = exercise.conditions;
  final runner = conditions.hands == HandConfiguration.together
      ? 'each hand'
      : 'the hand';

  return <(String term, String meaning)>[
    (
      materialName(exercise.material),
      'The scale to play. Its notes are the ones the exercise is asking you '
          'to remember.',
    ),
    (
      handsName(conditions.hands),
      switch (conditions.hands) {
        HandConfiguration.right => 'The right hand plays alone.',
        HandConfiguration.left => 'The left hand plays alone.',
        HandConfiguration.together =>
          'Both hands play, each in its own register, arriving together.',
      },
    ),
    (
      traversalName(conditions),
      switch ((conditions.handMotion, conditions.direction)) {
        (HandMotion.contrary, ScaleDirection.up) =>
          'Both hands start on ${tonicName(exercise.material)} and move apart, '
              'the right going up as the left goes down, stopping at their '
              'outer notes.',
        (HandMotion.contrary, ScaleDirection.upDown) =>
          'Both hands start on ${tonicName(exercise.material)} and move apart, '
              'the right going up as the left goes down, then back together '
              'again.',
        (_, ScaleDirection.up) =>
          'Start on ${tonicName(exercise.material)}, go up to the top note, '
              'and stop there.',
        (_, ScaleDirection.upDown) =>
          'Start on ${tonicName(exercise.material)}, go up to the top note, '
              'then back down again.',
      },
    ),
    (
      octavesName(conditions.octaves),
      switch (conditions.direction) {
        ScaleDirection.up => 'How far $runner runs before it stops.',
        ScaleDirection.upDown => 'How far $runner runs before it turns around.',
      },
    ),
    (
      '${conditions.tempoBpm.round()} bpm',
      'The speed to aim for, in beats per minute: one note to a beat. Four '
          'beats are counted in first, which is also your time to get your '
          'hands to the keys.',
    ),
  ];
}

class _TermHelp extends StatelessWidget {
  const _TermHelp({
    required this.title,
    required this.entries,
    this.introduction,
  });

  final String title;
  final String? introduction;
  final List<(String term, String meaning)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.readableWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (introduction case final introduction?) ...[
                  const SizedBox(height: 8),
                  Text(introduction, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 16),
                for (final (term, meaning) in entries) ...[
                  Text(term, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    meaning,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
