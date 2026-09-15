import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'practice_failure.dart';
import 'practice_providers.dart';

/// A practice failure, and the ways out that its kind actually has.
///
/// They are not interchangeable. A journal this build cannot replay is the
/// only one erasing answers, and it erases the profile the failure named; a
/// selection nobody can read is repaired by forgetting it, which destroys
/// nothing; a genesis that cannot be read has no safe repair at all; an
/// attempt that did not reach history is still here to write, and reopening
/// would find its decision pending and its performance gone; a decision that
/// failed asks again on a sitting nothing is wrong with; a stored plan nobody
/// can read says the same thing every time it is read, so it is the one
/// failure with nothing to ask again and replacing it is the only way on.
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

  /// What went wrong, from a classified failure.
  ///
  /// Anything unclassified is [PracticeFailure.opening]: a sitting that never
  /// opened, for a reason nothing here established. Reading it as an
  /// unreadable history would offer to destroy a journal nobody found fault
  /// with.
  PracticeFailure get kind => switch (error) {
    PracticeLoopFailure(:final kind) => kind,
    _ => PracticeFailure.opening,
  };

  /// Whose artifact failed, where the failure named somebody.
  String? get profileId => switch (error) {
    PracticeLoopFailure(:final profileId) => profileId,
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(practiceLoopProvider.notifier);
    final target = profileId;
    // A null label is a failure asking again cannot answer, so no retry is
    // offered for it.
    final (title, explanation, String? retryLabel) = switch (kind) {
      PracticeFailure.history => (
        'This practice history could not be opened.',
        'Try again first. If it keeps failing, starting over is the only '
            'way in, and it throws away everything recorded so far.',
        'Try again',
      ),
      PracticeFailure.selection => (
        'Which profile to practice as could not be read.',
        'Nothing anybody practiced is affected. Forgetting the setting picks '
            'up the oldest profile on this install, and switching afterwards '
            'works as it always did.',
        'Try again',
      ),
      PracticeFailure.roster => (
        'A profile on this install could not be read.',
        'A profile records when it was created, and that is what everything '
            'it played is measured from, so there is nothing safe to rebuild '
            'it as. If a backup of this install exists, it is the way back.',
        'Try again',
      ),
      PracticeFailure.deletion => (
        'A profile this install was removing could not be read.',
        'The record of what was being deleted is what says which profile it '
            'was, so nothing here can finish the job or call it off. Nothing '
            'further will be removed automatically.',
        'Try again',
      ),
      PracticeFailure.opening => (
        'Practice could not be started.',
        'Nothing recorded has been touched. Try again, and if it keeps '
            'failing the message below is what to report.',
        'Try again',
      ),
      PracticeFailure.commit => (
        'This attempt has not been saved yet.',
        'What was played is still here. Saving it again records the same '
            'attempt, so nothing about it changes and nothing is counted '
            'twice.',
        'Save this attempt again',
      ),
      PracticeFailure.plan => (
        'This goal and focus could not be read.',
        'Nothing practiced is affected. What was stored asks for material '
            'this version does not recognize, so it is left alone rather than '
            'guessed at. Practicing normally replaces it with a goal over '
            'everything and no focus.',
        null,
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
        if (retryLabel != null)
          OutlinedButton(onPressed: notifier.retry, child: Text(retryLabel)),
        // Only where the history itself is what cannot be read, and only for
        // the profile the failure named. Offered beside an attempt that is
        // still savable, or aimed at whoever the app happened to be holding,
        // it destroys the practice it was meant to rescue.
        if (kind == PracticeFailure.history && target != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => notifier.eraseHistory(target),
            child: const Text('Erase this history and start over'),
          ),
        ],
        if (kind == PracticeFailure.plan) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref
                .read(practicePlanProvider.notifier)
                .apply(PracticePlan.normal),
            child: const Text('Practice normally instead'),
          ),
        ],
        if (kind == PracticeFailure.selection) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: notifier.repairSelection,
            child: const Text('Forget it and use the oldest profile'),
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
