import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:material_ui/material_ui.dart';

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

  Future<void> _connect(MidiDevice device) async {
    final generation = ++_selectionGeneration;
    setState(() => _error = null);
    try {
      await _connection.connect(device);
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

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(midiDeviceManagerProvider);
    final connection = ref.watch(midiConnectionStateProvider);
    final connected = connection.isConnected ? connection.device : null;
    final devices = [
      ?connected,
      ...manager.devices.where((device) => device.id != connected?.id),
    ];
    final theme = Theme.of(context);

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
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No instruments found yet.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isConnected = device.id == connected?.id;
                    final isConnecting =
                        connection.isAttemptingConnection &&
                        device.id == connection.device?.id;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: isConnected,
                      selectedTileColor: theme.colorScheme.primaryContainer,
                      selectedColor: theme.colorScheme.onPrimaryContainer,
                      title: Text(device.displayName ?? device.id),
                      subtitle: Text(
                        isConnected
                            ? '${device.transport.label} · Connected'
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
                      onTap: isConnecting ? null : () => _connect(device),
                    );
                  },
                ),
              ),
            if (connection.isAttemptingConnection || connection.isConnected)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Divider(height: 1),
              ),
            if (connection.isAttemptingConnection)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    _selectionGeneration++;
                    setState(() => _error = null);
                    unawaited(_connection.cancelConnectionAttempt());
                  },
                  child: const Text('Cancel'),
                ),
              ),
            if (connection.isConnected)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await _connection.disconnect();
                    if (context.mounted) setState(() => _error = null);
                  },
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Disconnect'),
                ),
              ),
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
    if (MediaQuery.disableAnimationsOf(context)) {
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
