import 'package:material_ui/material_ui.dart';

import 'task_help.dart';

const String attemptSummaryIntroduction =
    'These lines describe this attempt, not your overall skill level.';

List<(String term, String meaning)> attemptSummaryHelpEntries({
  required bool includesCoordination,
}) => [
  ('Notes', 'How closely the notes you played matched the exercise.'),
  (
    'Flow',
    'Whether you kept moving through the scale without stopping or breaking '
        'it up.',
  ),
  ('Pulse', 'How evenly the notes were spaced in time.'),
  if (includesCoordination)
    ('Coordination', 'How closely the two hands arrived together.'),
  (
    'Tempo',
    "Your overall playing speed compared with the exercise's target tempo.",
  ),
];

Future<void> showAttemptSummaryHelp(
  BuildContext context, {
  required bool includesCoordination,
  Widget? debugDetails,
}) => showTermHelp(
  context,
  title: 'What KeyRecall heard',
  introduction: attemptSummaryIntroduction,
  entries: attemptSummaryHelpEntries(
    includesCoordination: includesCoordination,
  ),
  appendixTitle: debugDetails == null ? null : 'Measurement details',
  appendix: debugDetails,
);
