import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'practice_providers.dart';

/// Who uses this install: switch between them, add one, rename one, put one
/// back at placement, or remove one entirely.
///
/// Two jobs at once, and both of them ordinary. One person keeps their own
/// practice separate from anybody else who sits at the same instrument. The
/// same screen is also how a change to the scheduler gets tried on a fresh
/// learner without disturbing a real history: make a throwaway profile, run it
/// forward, erase it, run it again.
///
/// Adding a profile switches to it, on the grounds that somebody adding one
/// is about to use it, and this list is how they switch back.
///
/// Erasing and deleting are kept apart on purpose. Erasing keeps the profile
/// and drops what it recorded, which is the one a test profile wants over and
/// over. Deleting takes the person as well, which is the one that should feel
/// heavier.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  @override
  void initState() {
    super.initState();
    // Read on arrival, every time. What each profile has recorded changes
    // while this screen is not on screen, since practicing is what changes it,
    // so a roster left over from the last visit is stale by construction.
    ref.invalidate(profileRosterProvider);
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(profileRosterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addProfile(context, ref),
        icon: const Icon(Icons.person_add),
        label: const Text('Add profile'),
      ),
      body: switch (roster) {
        AsyncError(:final error) => _Failure(error: error),
        // Whatever was last read stays up while the next read runs. Replacing
        // the list with a spinner every time a count is refreshed makes the
        // screen flicker on arrival and after every change.
        AsyncValue(hasValue: true, :final value?) => _Roster(value),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Roster extends ConsumerWidget {
  const _Roster(this.summaries);

  final List<ProfileSummary> summaries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (summaries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nobody uses this install yet. Add a profile, or open the '
            'practice loop and one will be made without asking.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      // Clear of the button that adds a profile.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: summaries.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _ProfileTile(summaries[index]),
    );
  }
}

class _ProfileTile extends ConsumerWidget {
  const _ProfileTile(this.summary);

  final ProfileSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = summary.profile;
    final notifier = ref.read(profileRosterProvider.notifier);

    return ListTile(
      leading: Icon(
        summary.isActive ? Icons.check_circle : Icons.circle_outlined,
        color: summary.isActive ? theme.colorScheme.primary : null,
      ),
      title: Text(profile.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_history(summary)),
          Text(
            profile.id,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
      isThreeLine: true,
      // Tapping switches, which is the thing this screen is opened for. Every
      // other action is one menu away, so none of them can happen by accident.
      onTap: summary.isActive ? null : () => notifier.select(profile.id),
      trailing: PopupMenuButton<_ProfileAction>(
        onSelected: (action) => _run(context, ref, action),
        itemBuilder: (context) => [
          if (!summary.isActive)
            const PopupMenuItem(
              value: _ProfileAction.select,
              child: Text('Practice as this profile'),
            ),
          const PopupMenuItem(
            value: _ProfileAction.rename,
            child: Text('Rename'),
          ),
          const PopupMenuItem(
            value: _ProfileAction.eraseHistory,
            child: Text('Erase history, keep the profile'),
          ),
          const PopupMenuItem(
            value: _ProfileAction.delete,
            child: Text('Delete profile and history'),
          ),
        ],
      ),
    );
  }

  /// What this profile has recorded, said in one line.
  static String _history(ProfileSummary summary) {
    if (summary.historyError != null) return 'history unreadable';
    final attempts = summary.attemptsRecorded ?? 0;
    final counted = attempts == 1 ? '1 attempt' : '$attempts attempts';
    final created = summary.profile.createdAt.toLocal();
    return '$counted · added ${created.year}-'
        '${created.month.toString().padLeft(2, '0')}-'
        '${created.day.toString().padLeft(2, '0')}';
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _ProfileAction action,
  ) async {
    final notifier = ref.read(profileRosterProvider.notifier);
    final profile = summary.profile;

    switch (action) {
      case _ProfileAction.select:
        await notifier.select(profile.id);
      case _ProfileAction.rename:
        final name = await _askForName(
          context,
          title: 'Rename profile',
          initial: profile.displayName,
          confirmLabel: 'Rename',
        );
        if (name != null) await notifier.rename(profile.id, name);
      case _ProfileAction.eraseHistory:
        final erase = await _confirm(
          context,
          title: 'Erase ${profile.displayName}’s history?',
          // Says what survives as well as what goes: erase and delete sit
          // next to each other in the menu, and the difference between them
          // is the whole reason both exist.
          message:
              'Every attempt recorded for this profile is deleted and the '
              'learner model goes back to placement. The profile itself '
              'stays. There is no undo.',
          confirmLabel: 'Erase',
        );
        if (erase) await notifier.eraseHistory(profile.id);
      case _ProfileAction.delete:
        final delete = await _confirm(
          context,
          title: 'Delete ${profile.displayName}?',
          message:
              'The profile and everything it recorded are deleted. There is '
              'no undo.',
          confirmLabel: 'Delete',
        );
        if (delete) await notifier.remove(profile.id);
    }
  }
}

/// What the menu on a profile offers.
enum _ProfileAction { select, rename, eraseHistory, delete }

/// Adds a profile and switches to it.
Future<void> _addProfile(BuildContext context, WidgetRef ref) async {
  final name = await _askForName(
    context,
    title: 'Add profile',
    initial: '',
    confirmLabel: 'Add',
  );
  if (name != null) await ref.read(profileRosterProvider.notifier).add(name);
}

/// Asks for a display name, refusing an empty one.
///
/// Empty is refused rather than accepted and cleaned up, because a profile
/// with no name is one nobody can pick out of the list.
Future<String?> _askForName(
  BuildContext context, {
  required String title,
  required String initial,
  required String confirmLabel,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _NameDialog(title: title, initial: initial, confirmLabel: confirmLabel),
);

/// The name prompt, stateful so the field's controller outlives the dialog's
/// closing animation.
///
/// Disposing it as soon as [showDialog] returns is too early: the route is
/// still on screen animating out, and the text field it is still building
/// reaches for a controller that is already gone.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}

/// Asks before something that cannot be undone.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _Failure extends ConsumerWidget {
  const _Failure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'The profile index could not be read. Nothing here guesses who '
        'exists from the directories on disk, because an id is an identity '
        'and guessing one would attach somebody to practice that is not '
        'theirs.',
      ),
      const SizedBox(height: 12),
      Text('$error', style: const TextStyle(fontFamily: 'monospace')),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => ref.invalidate(profileRosterProvider),
        child: const Text('Try again'),
      ),
    ],
  );
}
