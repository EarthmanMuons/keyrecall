import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'practice_failure.dart';
import 'practice_providers.dart';

/// A practice failure, and the ways out that its kind actually has.
///
/// The three are not interchangeable. A journal this build cannot replay is
/// the only one erasing answers; an attempt that did not reach history is
/// still here to write, and reopening would find its decision pending and its
/// performance gone; a decision that failed asks again on a sitting nothing is
/// wrong with.
class LoopFailure extends ConsumerWidget {
  const LoopFailure({
    required this.error,
    this.stackTrace,
    this.showsStackTrace = false,
    super.key,
  });

  final Object error;
  final StackTrace? stackTrace;
  final bool showsStackTrace;

  /// What went wrong, from a classified failure or from anything else, which
  /// is a sitting that never opened.
  PracticeFailure get kind => switch (error) {
    PracticeLoopFailure(:final kind) => kind,
    _ => PracticeFailure.history,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(practiceLoopProvider.notifier);
    final (title, explanation, retryLabel) = switch (kind) {
      PracticeFailure.history => (
        'This practice history could not be opened.',
        'Try again first. If it keeps failing, starting over is the only '
            'way in, and it throws away everything recorded so far.',
        'Try again',
      ),
      PracticeFailure.commit => (
        'This attempt has not been saved yet.',
        'What was played is still here. Saving it again records the same '
            'attempt, so nothing about it changes and nothing is counted '
            'twice.',
        'Save this attempt again',
      ),
      PracticeFailure.scheduling => (
        'The next exercise could not be chosen.',
        'Everything practiced so far is recorded. Nothing is lost by asking '
            'again.',
        'Try again',
      ),
    };

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(explanation, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Text(
          '$error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: notifier.retry, child: Text(retryLabel)),
        // Only where the history itself is what cannot be read. Offered beside
        // an attempt that is still savable, it destroys the practice it was
        // meant to rescue.
        if (kind == PracticeFailure.history) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: notifier.eraseHistory,
            child: const Text('Erase this history and start over'),
          ),
        ],
        if (showsStackTrace && stackTrace != null) ...[
          const SizedBox(height: 24),
          Text('$stackTrace', style: const TextStyle(fontFamily: 'monospace')),
        ],
      ],
    );
  }
}
