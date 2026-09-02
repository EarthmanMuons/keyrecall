import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:material_ui/material_ui.dart';

import 'placement.dart';
import 'practice_providers.dart';
import 'profile_avatar.dart';
import 'profile_color.dart';

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
    //
    // After the frame that pushed this route: invalidating while the route is
    // still being built marks the scope above it dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(profileRosterProvider);
    });
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
    if (summaries.isEmpty) return const _NobodyHere();

    return ListView.separated(
      // Clear of the button that adds a profile.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: summaries.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _ProfileTile(summaries[index]),
    );
  }
}

/// An install with nobody on it.
///
/// Reached by deleting the last profile, so it says what the screen is for
/// rather than only that it is empty. Sat above the centre line, clear of the
/// button that answers it.
class _NobodyHere extends StatelessWidget {
  const _NobodyHere();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: const Alignment(0, -0.3),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline,
                size: 44,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 20),
              Text(
                'Nobody practices here yet',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Add a profile to start practicing. Everyone who plays here '
                'gets their own history and progress.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends ConsumerWidget {
  const _ProfileTile(this.summary);

  final ProfileSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = summary.profile;
    final notifier = ref.read(profileRosterProvider.notifier);

    return ListTile(
      leading: _ProfileMark(profile: profile, isActive: summary.isActive),
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
            value: _ProfileAction.edit,
            child: Text('Edit profile'),
          ),
          const PopupMenuItem(
            value: _ProfileAction.eraseHistory,
            child: Text('Clear history'),
          ),
          const PopupMenuItem(
            value: _ProfileAction.delete,
            child: Text('Delete profile'),
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
      case _ProfileAction.edit:
        final edits = await _editProfile(context, profile);
        if (edits == null) return;
        if (edits.name != profile.displayName) {
          await notifier.rename(profile.id, edits.name);
        }
        if (edits.color != ProfileColor.of(profile)) {
          await notifier.recolor(profile.id, edits.color);
        }
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
enum _ProfileAction { select, edit, eraseHistory, delete }

/// The profile's disc, marked when this is the one being practiced as.
///
/// The mark is filled with the accent and ringed in the page's own colour, so
/// it reads as an object sitting on the disc rather than as part of it, even
/// where the profile's colour is close to the accent.
class _ProfileMark extends StatelessWidget {
  const _ProfileMark({required this.profile, required this.isActive});

  final Profile profile;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatar = ProfileAvatar(profile: profile);
    if (!isActive) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
            ),
            child: Icon(Icons.check, size: 11, color: scheme.surface),
          ),
        ),
      ],
    );
  }
}

/// How a profile is recognized: what it is called, and the colour it wears.
///
/// One dialog because it is one decision. A name and a colour are both answers
/// to the same question of which row in the list is yours, and asking them
/// separately made changing both a trip through the menu twice.
///
/// Returns null when nothing was confirmed.
Future<({String name, ProfileColor color})?> _editProfile(
  BuildContext context,
  Profile profile,
) => showDialog<({String name, ProfileColor color})>(
  context: context,
  builder: (context) => _ProfileDialog(profile),
);

/// The editor, stateful so the field's controller outlives the dialog's
/// closing animation; see [_NameDialog].
class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog(this.profile);

  final Profile profile;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.profile.displayName,
  );
  late ProfileColor _color = ProfileColor.of(widget.profile);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Empty is refused rather than accepted and cleaned up, because a profile
  /// with no name is one nobody can pick out of the list.
  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((name: name, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Edit profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          Text('Colour', style: theme.textTheme.labelLarge),
          const SizedBox(height: 12),
          // The palette is the whole choice. A colour is what a profile is
          // picked out by at a glance, so the six that stay apart are the six
          // on offer.
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final color in ProfileColor.values)
                InkResponse(
                  onTap: () => setState(() => _color = color),
                  radius: 28,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: color.color,
                    child: color == _color
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

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
