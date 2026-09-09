import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'attempt_review.dart';
import 'exercise_presentation.dart';

/// What just happened in a supported attempt, and what comes next.
///
/// The same shape and cadence as the ordinary review, and deliberately without
/// its channels. Supported work produces no outcome, so there is nothing to
/// score and nothing about notes, flow, pulse or tempo to report. What this
/// screen is for is the part the ordinary review does that has nothing to do
/// with scoring: closing one piece of work before the next begins.
///
/// Going straight from a finished attempt to another Ready screen was the
/// alternative, and it read as the app skipping a step. It also left the one
/// thing worth saying unsaid, because the line that explains a restored tempo
/// lives on a review, and acquisition had none.
class AcquisitionReview extends StatelessWidget {
  const AcquisitionReview({
    required this.record,
    required this.onNext,
    this.next,
    this.continues = false,
    super.key,
  });

  /// The supported attempt that just closed.
  final AcquisitionAttemptRecord record;

  /// What has been decided to come next, if anything.
  final NextPracticePreview? next;

  final VoidCallback onNext;

  /// Whether anything follows this transition.
  final bool continues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final upcoming = next;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                materialName(record.parent.material),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // States what happened and stops there. Whether it was good is a
              // question supported work does not answer, and a screen that
              // implied an answer would be making the claim the whole design
              // exists to withhold.
              Text(
                record.completion.isComplete
                    ? 'You played it all the way through, at your own pace.'
                    : 'Not all of it came out that time.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              if (upcoming != null) ...[
                Text(
                  'Next exercise',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  materialName(upcoming.material),
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                if (upcoming.explanation case final explanation?) ...[
                  const SizedBox(height: 4),
                  Text(
                    explanation,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
              ],
              SizedBox(
                height: 88,
                child: FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    textStyle: theme.textTheme.headlineSmall,
                  ),
                  child: Text(
                    upcoming == null && !continues ? 'Done' : 'Continue',
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
