import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'exercise_presentation.dart';

/// What each line of the task statement means, for the exercise on screen.
///
/// Written against this exercise rather than in general: somebody asking what
/// "Up and down" means is looking at those words, and a glossary of every term
/// the app can produce would make them find their own again.
Future<void> showTaskHelp(BuildContext context, Exercise exercise) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _TaskHelp(exercise),
    );

/// What each term on the task statement means, in the order the statement
/// puts them.
///
/// The terms are produced by the same naming this app writes on the statement,
/// so the entry somebody is looking for reads exactly as the line they tapped.
List<(String term, String meaning)> taskHelpEntries(Exercise exercise) {
  final conditions = exercise.conditions;

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
      directionName(conditions.direction),
      switch (conditions.direction) {
        ScaleDirection.up => 'Up to the top note, and stop there.',
        ScaleDirection.upDown => 'Up to the top note, then back down again.',
      },
    ),
    (
      octavesName(conditions.octaves),
      'How far the scale runs before it stops or turns around.',
    ),
    (
      '${conditions.tempoBpm.round()} bpm',
      'The speed to aim for, in beats per minute: one note to a beat. Four '
          'beats are counted in first, which is also your time to get your '
          'hands to the keys.',
    ),
  ];
}

/// The one thing the statement does not say.
///
/// Scoring is register-relative, so a learner who assumed otherwise is holding
/// a rule the app does not have.
const String taskHelpRegisterNote =
    'Any octave counts. Start where your hand falls: playing the whole scale '
    'higher or lower than it is written is the same scale, and is read as one.';

class _TaskHelp extends StatelessWidget {
  const _TaskHelp(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final entries = taskHelpEntries(exercise);

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
                Text('What this asks for', style: theme.textTheme.titleLarge),
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
                Text(taskHelpRegisterNote, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
