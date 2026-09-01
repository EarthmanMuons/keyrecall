import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'placement.dart';
import 'profile_avatar.dart';
import 'profile_color.dart';
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
            'Nobody practices here yet. Add a profile to get started.',
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
      leading: Badge(
        isLabelVisible: summary.isActive,
        backgroundColor: theme.colorScheme.primary,
        label: const Icon(Icons.check, size: 10),
        child: ProfileAvatar(profile: profile),
      ),
      title: Text(
        profile.displayName,
        style: summary.isActive
            ? const TextStyle(fontWeight: FontWeight.w600)
            : null,
      ),
      subtitle: Text(_history(summary)),
      // Tapping switches, which is the thing this screen is opened for. Every
      // other action is one menu away, so none of them can happen by accident.
      onTap: summary.isActive
          ? null
          : () => _switchTo(context, notifier, profile),
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
            value: _ProfileAction.recolor,
            child: Text('Change color'),
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

  /// Switches, and says so.
  ///
  /// The list marks who is active, but the tap that changed it also leaves the
  /// screen a moment later, so the confirmation names the person rather than
  /// leaving somebody to check the mark on their way out.
  static Future<void> _switchTo(
    BuildContext context,
    ProfileRosterNotifier notifier,
    Profile profile,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await notifier.select(profile.id);
    messenger.showSnackBar(
      SnackBar(content: Text('Now practicing as ${profile.displayName}')),
    );
  }

  /// What this profile has recorded, said in one line.
  static String _history(ProfileSummary summary) {
    if (summary.historyError != null) return 'history could not be read';
    // Counted rather than judged. A recorded attempt can be one somebody
    // declined or walked away from, so anything saying they were completed
    // would be claiming more than the number knows.
    final attempts = summary.attemptsRecorded ?? 0;
    final counted = switch (attempts) {
      0 => 'nothing played yet',
      1 => '1 exercise',
      _ => '$attempts exercises',
    };
    final created = summary.profile.createdAt.toLocal();
    // The placement is shown because nothing can change it. A permanent
    // answer somebody gave once should at least be readable back.
    return '$counted · ${summary.profile.placement.label} · added '
        '${created.year}-'
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
      case _ProfileAction.recolor:
        final color = await _askForColor(context, profile);
        if (color != null) await notifier.recolor(profile.id, color);
      case _ProfileAction.eraseHistory:
        final erase = await _confirm(
          context,
          title: 'Erase ${profile.displayName}’s history?',
          // Says what survives as well as what goes: erase and delete sit
          // next to each other in the menu, and the difference between them
          // is the whole reason both exist.
          message:
              'Every attempt recorded for this profile is deleted, and '
              'practice starts again from where they were first placed. The '
              'profile itself stays. This cannot be undone.',
          confirmLabel: 'Erase',
        );
        if (erase) await notifier.eraseHistory(profile.id);
      case _ProfileAction.delete:
        final delete = await _confirm(
          context,
          title: 'Delete ${profile.displayName}?',
          message:
              'The profile and everything it recorded are deleted. This '
              'cannot be undone.',
          confirmLabel: 'Delete',
        );
        if (delete) await notifier.remove(profile.id);
    }
  }
}

/// What the menu on a profile offers.
enum _ProfileAction { select, rename, recolor, eraseHistory, delete }

/// Asks which colour to show a profile in, or null when nobody chose.
///
/// The palette is the whole choice. A colour is what a profile is picked out
/// by at a glance, so the six that stay apart are the six on offer.
Future<ProfileColor?> _askForColor(BuildContext context, Profile profile) =>
    showDialog<ProfileColor>(
      context: context,
      builder: (context) {
        final current = ProfileColor.of(profile);
        return AlertDialog(
          title: Text('Colour for ${profile.displayName}'),
          content: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final color in ProfileColor.values)
                InkResponse(
                  onTap: () => Navigator.of(context).pop(color),
                  radius: 28,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: color.color,
                    child: color == current
                        ? Icon(
                            Icons.check,
                            color:
                                ThemeData.estimateBrightnessForColor(
                                      color.color,
                                    ) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                          )
                        : null,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

/// Adds a profile and switches to it.
Future<void> _addProfile(BuildContext context, WidgetRef ref) async {
  final name = await _askForName(
    context,
    title: 'Add profile',
    initial: '',
    confirmLabel: 'Add',
  );
  if (name == null || !context.mounted) return;

  final placement = await askForPlacement(context);
  if (placement == null) return;

  await ref.read(profileRosterProvider.notifier).add(name, placement);
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

/// A roster that could not be read.
///
/// Nothing here guesses who exists from the directories on disk: an id is an
/// identity, and guessing one would attach somebody to practice that is not
/// theirs.
class _Failure extends ConsumerWidget {
  const _Failure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'The list of profiles could not be read, so nobody can be shown here. '
        'Practice that is already recorded is untouched.',
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
