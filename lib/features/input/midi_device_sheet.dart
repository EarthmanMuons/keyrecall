import 'dart:async';

import 'package:flutter/semantics.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:material_ui/material_ui.dart';

import '../../motion.dart';
import 'input_source.dart';

/// Discover instruments and manage the current MIDI connection.
class MidiDeviceSheet extends ConsumerStatefulWidget {
  const MidiDeviceSheet({super.key});

  /// Opens the sheet, returning the device connected to, if any.
  static Future<MidiDevice?> show(BuildContext context) =>
      showModalBottomSheet<MidiDevice>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => const MidiDeviceSheet(),
      );

  @override
  ConsumerState<MidiDeviceSheet> createState() => _MidiDeviceSheetState();
}

class _MidiDeviceSheetState extends ConsumerState<MidiDeviceSheet> {
  late final MidiConnectionNotifier _connection;
  String? _error;
  int _selectionGeneration = 0;
  String? _swipedAwayId;

  @override
  void initState() {
    super.initState();
    _connection = ref.read(midiConnectionStateProvider.notifier);
    // After the first frame, so the sheet is on screen before the radio work
    // starts.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_scan()));
  }

  @override
  void dispose() {
    // Scanning is expensive and nothing else here wants it running.
    unawaited(_connection.stopScanning());
    super.dispose();
  }

  Future<void> _scan() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      await _connection.refreshDevices();
    } on MidiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  /// Connects to [device], reaching one the scan has not [found] through the
  /// reconnect path, which waits for it to appear.
  Future<void> _connect(MidiDevice device, {required bool found}) async {
    final generation = ++_selectionGeneration;
    setState(() => _error = null);
    try {
      if (found) {
        await _connection.connect(device);
      } else {
        await _connection.reconnect();
      }
    } catch (error) {
      if (!mounted || generation != _selectionGeneration) return;
      setState(() {
        _error = error is MidiException ? error.message : 'Could not connect.';
      });
      return;
    }
    if (!mounted || generation != _selectionGeneration) return;

    final state = ref.read(midiConnectionStateProvider);
    if (state.isConnected && state.device?.id == device.id) {
      Navigator.of(context).pop(state.device);
    } else {
      setState(() => _error = state.message ?? 'Could not connect.');
    }
  }

  Future<void> _forget(MidiDevice remembered) async {
    final connection = ref.read(midiConnectionStateProvider);
    if (connection.isAttemptingConnection &&
        connection.device?.id == remembered.id) {
      _selectionGeneration++;
    }
    await _connection.forget();
    if (mounted) {
      setState(() {
        _error = null;
        _swipedAwayId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(midiDeviceManagerProvider);
    final connection = ref.watch(midiConnectionStateProvider);
    final connected = connection.isConnected ? connection.device : null;
    final remembered = ref.watch(lastConnectedMidiDeviceProvider);
    final found = {for (final device in manager.devices) device.id: device};
    final listedRemembered =
        remembered?.id == connected?.id || remembered?.id == _swipedAwayId
        ? null
        : found[remembered?.id] ?? remembered;
    final yours = [?connected, ?listedRemembered];
    final others = manager.devices
        .where(
          (device) => device.id != connected?.id && device.id != remembered?.id,
        )
        .toList();
    final theme = Theme.of(context);

    Widget deviceTile(MidiDevice device) {
      final isConnected = device.id == connected?.id;
      final isConnecting =
          connection.isAttemptingConnection &&
          device.id == connection.device?.id;
      final isRemembered = device.id == remembered?.id;
      final isFound = found.containsKey(device.id);
      // Keep tile ink inside the scroll viewport.
      final tile = Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          // A swipeable row is rounded by its clip instead, so the tile's
          // edge meets the swipe background flush.
          shape: isRemembered
              ? null
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          selected: isConnected,
          selectedTileColor: theme.colorScheme.primaryContainer,
          selectedColor: theme.colorScheme.onPrimaryContainer,
          title: Text(device.displayName ?? device.id),
          subtitle: Text(
            isConnected
                ? '${device.transport.label} · Connected'
                : !isFound && !isConnecting
                ? '${device.transport.label} · Not found'
                : device.transport.label,
          ),
          trailing: isConnecting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : isConnected
              ? const Icon(Icons.check_circle_outline)
              : null,
          onTap: isConnecting
              ? null
              : () => _connect(device, found: isConnected || isFound),
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: !isRemembered
            ? tile
            : Semantics(
                customSemanticsActions: {
                  const CustomSemanticsAction(label: 'Forget'): () =>
                      unawaited(_forget(device)),
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Dismissible(
                    key: ValueKey('remembered ${device.id}'),
                    direction: DismissDirection.endToStart,
                    background: const _ForgetSwipeBackground(),
                    // A device the scan sees stays listed, so its row
                    // springs back rather than leaving.
                    confirmDismiss: (_) async {
                      if (!isConnected && !isFound) return true;
                      await _forget(device);
                      return false;
                    },
                    onDismissed: (_) {
                      setState(() => _swipedAwayId = device.id);
                      unawaited(_forget(device));
                    },
                    child: tile,
                  ),
                ),
              ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'MIDI instruments',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (!manager.isScanning)
                  IconButton(
                    tooltip: 'Scan again',
                    onPressed: _scan,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (manager.isScanning) const _ScanningStatus(),
            if (!connection.isConnected) ...[
              const SizedBox(height: 4),
              Text(
                _statusOf(connection),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: connection.phase == MidiConnectionPhase.error
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            // A domain that is recognized and not authorized is a standing
            // fact about this connection rather than something a longer
            // attempt would fix, so it is said once, here, and not on every
            // attempt. Nothing is said while the clock is still being
            // identified: the first notes of an observation are expected to
            // be untimed.
            if (ref.watch(clockAuthorizationProvider) ==
                ClockAuthorization.nonPerformance) ...[
              const SizedBox(height: 8),
              Text(
                'Timing feedback unavailable with this connection. '
                'Note accuracy and completion are still measured.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null && _error != connection.message) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (yours.isEmpty && others.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No instruments found yet.'),
              )
            else
              Flexible(
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    if (yours.isNotEmpty) ...[
                      const _SectionLabel('Saved'),
                      for (final device in yours) deviceTile(device),
                      if (others.isNotEmpty) const _SectionLabel('Available'),
                    ],
                    for (final device in others) deviceTile(device),
                  ],
                ),
              ),
            if (connection.isAttemptingConnection ||
                connection.isConnected ||
                remembered != null) ...[
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Divider(height: 1),
              ),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: remembered == null
                      ? WrapAlignment.end
                      : WrapAlignment.spaceBetween,
                  children: [
                    if (remembered != null)
                      TextButton.icon(
                        onPressed: () => _forget(remembered),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Forget'),
                      ),
                    if (connection.isAttemptingConnection)
                      TextButton(
                        onPressed: () {
                          _selectionGeneration++;
                          setState(() => _error = null);
                          unawaited(_connection.cancelConnectionAttempt());
                        },
                        child: const Text('Cancel'),
                      )
                    else if (connection.isConnected)
                      TextButton.icon(
                        onPressed: () async {
                          await _connection.disconnect();
                          if (context.mounted) setState(() => _error = null);
                        },
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('Disconnect'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _statusOf(MidiConnectionState connection) =>
      switch (connection.phase) {
        MidiConnectionPhase.connected =>
          'Connected to ${connection.deviceDisplayName ?? 'an instrument'}',
        MidiConnectionPhase.connecting => 'Connecting',
        MidiConnectionPhase.retrying =>
          'Trying again, attempt ${connection.attempt}',
        MidiConnectionPhase.error => connection.message ?? 'Could not connect.',
        _ => 'Not connected',
      };
}

class _ForgetSwipeBackground extends StatelessWidget {
  const _ForgetSwipeBackground();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Forget',
              style: TextStyle(
                color: colors.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.delete_outline, color: colors.onErrorContainer),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ScanningStatus extends StatefulWidget {
  const _ScanningStatus();

  @override
  State<_ScanningStatus> createState() => _ScanningStatusState();
}

class _ScanningStatusState extends State<_ScanningStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.35,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.of(context).reduced) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      unawaited(_pulse.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        FadeTransition(
          opacity: _pulse,
          child: Icon(
            Icons.bluetooth_searching,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Scanning for instruments',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
