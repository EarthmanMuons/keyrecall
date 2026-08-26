import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:material_ui/material_ui.dart';

/// Scan for a MIDI instrument, connect to one, and see what happened.
///
/// The smallest surface that makes the vendored transport usable on real
/// hardware: everything below it, including retries, auto-reconnect, and
/// remembering the last device, already exists in `keyrecall_midi`. Modeled on
/// WhatChord's picker without bringing its design across, and not a settings
/// screen: Bluetooth permission prompts, transport explanations, and status
/// affordances belong to a real design rather than to a debug sheet.
class MidiDeviceSheet extends ConsumerStatefulWidget {
  const MidiDeviceSheet({super.key});

  /// Opens the sheet, returning the device connected to, if any.
  static Future<MidiDevice?> show(BuildContext context) =>
      showModalBottomSheet<MidiDevice>(
        context: context,
        isScrollControlled: true,
        builder: (context) => const MidiDeviceSheet(),
      );

  @override
  ConsumerState<MidiDeviceSheet> createState() => _MidiDeviceSheetState();
}

class _MidiDeviceSheetState extends ConsumerState<MidiDeviceSheet> {
  late final MidiConnectionNotifier _connection;
  String? _error;

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
    setState(() => _error = null);
    try {
      await _connection.refreshDevices();
    } on MidiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _connect(MidiDevice device) async {
    setState(() => _error = null);
    await _connection.connect(device);
    if (!mounted) return;

    final state = ref.read(midiConnectionStateProvider);
    if (state.isConnected) {
      Navigator.of(context).pop(state.device);
    } else {
      setState(() => _error = state.message ?? 'could not connect');
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(midiDeviceManagerProvider).devices;
    final isScanning = ref.watch(midiDeviceManagerProvider).isScanning;
    final connection = ref.watch(midiConnectionStateProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'MIDI instruments',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isScanning)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: 'Scan again',
                    onPressed: _scan,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            Text(
              _statusOf(connection),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nothing found yet.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final device in devices)
                      ListTile(
                        title: Text(device.displayName ?? device.id),
                        subtitle: Text(device.transport.label),
                        trailing: device.id == connection.device?.id
                            ? const Icon(Icons.link)
                            : null,
                        onTap: connection.isAttemptingConnection
                            ? null
                            : () => _connect(device),
                      ),
                  ],
                ),
              ),
            if (connection.isConnected)
              TextButton(
                onPressed: () async {
                  await _connection.disconnect();
                  if (context.mounted) setState(() {});
                },
                child: const Text('Disconnect'),
              ),
          ],
        ),
      ),
    );
  }

  static String _statusOf(MidiConnectionState connection) =>
      switch (connection.phase) {
        MidiConnectionPhase.connected =>
          'connected to ${connection.deviceDisplayName ?? 'an instrument'}',
        MidiConnectionPhase.connecting => 'connecting',
        MidiConnectionPhase.retrying =>
          'retrying, attempt ${connection.attempt}',
        MidiConnectionPhase.error => connection.message ?? 'connection failed',
        _ => 'not connected',
      };
}
