import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_mark.dart';
import '../../layout.dart';
import '../../wordmark.dart';
import '../input/input.dart';
import 'attempt_screen.dart';
import 'placement.dart';
import 'practice_providers.dart';

/// The practice app, behind the two moments a first launch has to spend.
///
/// The gate is whether this install has anybody on it, read from the roster
/// rather than from a flag: an install with a profile has been placed, and one
/// without has not. It holds however the roster emptied, so deleting the last
/// profile puts the install back here rather than conjuring a replacement
/// placed at a tier nobody chose. The practice loop refuses to open a sitting
/// without a profile, and this is what keeps that unreachable.
///
/// A roster that cannot be read falls through to the app, which has its own
/// account of unreadable storage and the ways out of it.
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(profileRosterProvider)) {
        AsyncData(:final value) when value.isEmpty => const Onboarding(),
        AsyncData() || AsyncError() => const AttemptScreen(),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
      };
}

/// A first launch: what the app is and where to start, then the instrument.
///
/// Two steps rather than a carousel, and the profile is written at the end of
/// the second. Until then nothing has been committed, so quitting halfway
/// leaves the install unplaced rather than placed at a tier that was never
/// confirmed.
class Onboarding extends ConsumerStatefulWidget {
  const Onboarding({super.key});

  @override
  ConsumerState<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<Onboarding> {
  PlacementTier? _tier;
  bool _isReadying = false;

  void _continue(PlacementTier tier) => setState(() {
    _tier = tier;
    _isReadying = true;
  });

  void _startPracticing() =>
      ref.read(profileRosterProvider.notifier).place(_tier!);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: _isReadying
          ? _ReadyStep(onStart: _startPracticing)
          : _WelcomeStep(selected: _tier, onContinue: _continue),
    ),
  );
}

/// What KeyRecall is, and the one question it needs answered.
class _WelcomeStep extends StatefulWidget {
  const _WelcomeStep({required this.selected, required this.onContinue});

  final PlacementTier? selected;
  final void Function(PlacementTier) onContinue;

  @override
  State<_WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<_WelcomeStep> {
  late PlacementTier? _selected = widget.selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _OnboardingPage(
      children: [
        const Center(child: AppMark()),
        const SizedBox(height: 10),
        Center(child: Wordmark(style: theme.textTheme.titleMedium)),
        const SizedBox(height: 28),
        Text(
          'Practice scales.\nWe’ll choose what comes next.',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          'KeyRecall learns from how you play and adjusts what you practice '
          'as your skills develop.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        Text(placementQuestion, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          placementReassurance,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        PlacementChoices(
          selected: _selected,
          onSelected: (tier) => setState(() => _selected = tier),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => widget.onContinue(_selected!),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

/// Getting an instrument attached, and how little there is to know.
class _ReadyStep extends ConsumerWidget {
  const _ReadyStep({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Only for the real instrument: reading the connection state starts the
    // Bluetooth stack, which the synthetic source has no use for.
    final needsInstrument = ref.watch(inputSourceProvider).requiresInstrument;

    return _OnboardingPage(
      children: [
        // The mark the practice bar carries for the instrument, so the button
        // that leads back here is recognizable when it is needed.
        Align(
          alignment: Alignment.centerLeft,
          child: Icon(
            Icons.piano,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text('Connect your piano', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'KeyRecall listens through MIDI. Connect your keyboard by USB or '
          'Bluetooth, and you are ready to practice.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (needsInstrument) ...[
          const _KeyboardStatus(),
          const SizedBox(height: 28),
        ],
        Text('Practice is simple', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (index, step) in const [
          'See the exercise.',
          'Tap Ready and play.',
          'KeyRecall chooses what comes next.',
        ].indexed) ...[
          _PracticeStep(number: index + 1, text: step),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 14),
        Text(
          'Practice for as long or as little as you want. There are no '
          'sessions to finish.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(onPressed: onStart, child: const Text('Start practicing')),
      ],
    );
  }
}

/// Whether an instrument has turned up yet, and the way to go looking.
class _KeyboardStatus extends ConsumerWidget {
  const _KeyboardStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connection = ref.watch(midiConnectionStateProvider);
    final isConnected = connection.isConnected;

    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isConnected ? Icons.check_circle : Icons.piano_off,
              color: isConnected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Keyboard', style: theme.textTheme.labelMedium),
                  Text(
                    isConnected
                        ? '${connection.deviceDisplayName ?? 'An instrument'} '
                              'connected'
                        : 'Waiting for a MIDI keyboard',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => MidiDeviceSheet.show(context),
              child: Text(isConnected ? 'Change' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One numbered line of the whole instruction manual.
class _PracticeStep extends StatelessWidget {
  const _PracticeStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '$number.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// The frame both steps sit in.
class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: EdgeInsets.all(Layout.of(context).gutter),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}
