import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'practice_providers.dart';

/// A sitting that could not be opened, and the two ways out of it.
///
/// The usual cause is a journal recorded under a learner model this build no
/// longer runs, which a retry cannot change. Erasing says what it destroys
/// rather than sitting beside Try again as if it were another attempt at the
/// same thing.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Practice could not be opened.',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text('$error', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => ref.invalidate(practiceLoopProvider),
          child: const Text('Try again'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () =>
              ref.read(practiceLoopProvider.notifier).eraseHistory(),
          child: const Text('Erase this history and start over'),
        ),
        if (showsStackTrace && stackTrace != null) ...[
          const SizedBox(height: 24),
          Text('$stackTrace', style: const TextStyle(fontFamily: 'monospace')),
        ],
      ],
    );
  }
}
