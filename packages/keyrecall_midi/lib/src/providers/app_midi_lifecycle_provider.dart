import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../midi_debug.dart';
import '../models/midi_connection.dart';
import '../providers/midi_connection_notifier.dart';
import '../providers/midi_device_manager.dart';
import '../providers/midi_input_notifier.dart';
import '../providers/midi_preferences_notifier.dart';

/// Installs app-wide MIDI lifecycle handling to coordinate behavior across
/// background and foreground transitions.
final appMidiLifecycleProvider = Provider<void>((ref) {
  final controller = _MidiLifecycleController(ref);
  controller._attach();
  ref.onDispose(controller._detach);
});

class _MidiLifecycleController with WidgetsBindingObserver {
  final Ref _ref;
  _MidiLifecycleController(this._ref);

  static const bool _debugLog = midiDebug;

  bool _attached = false;

  void _attach() {
    if (_attached) return;
    _attached = true;
    if (_debugLog) debugPrint('[LIFE] attach');
    WidgetsBinding.instance.addObserver(this);

    // Ensure the MIDI device manager is created early so it can install listeners and seed state.
    _ref.read(midiDeviceManagerProvider);
    // The input boundary has to exist before the first note, not after the
    // first listener: a suspension cannot end an observation nobody opened.
    _ref.read(midiInputProvider);

    // Attempt reconnect at startup (foreground).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefs = _ref.read(midiPreferencesProvider);
      final lastConnectedId = prefs.lastConnectedDeviceId;

      if (_debugLog) {
        debugPrint(
          '[LIFE] startup autoReconnect=${prefs.autoReconnect} '
          'lastId=${lastConnectedId ?? "null"}',
        );
      }
      if (prefs.autoReconnect &&
          lastConnectedId != null &&
          lastConnectedId.trim().isNotEmpty) {
        unawaited(
          _ref
              .read(midiConnectionStateProvider.notifier)
              .tryAutoReconnect(reason: MidiReconnectTrigger.startup),
        );
      }
    });
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    if (_debugLog) debugPrint('[LIFE] detach');
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final connectionState = _ref.read(midiConnectionStateProvider.notifier);
    final midi = _ref.read(midiDeviceManagerProvider.notifier);
    final input = _ref.read(midiInputProvider.notifier);

    if (_debugLog) debugPrint('[LIFE] state=$state');
    switch (state) {
      case AppLifecycleState.resumed:
        midi.setBackgrounded(false);
        connectionState.setBackgrounded(false);
        // A new observation, not a continuation of the suspended one.
        input.resumeObservation();

        // On iOS especially, the OS may drop Bluetooth connections while the
        // app is backgrounded with no watchdog running. Reconcile first so a
        // stale "Connected" state does not persist and short-circuit
        // reconnect.
        unawaited(
          Future<void>.microtask(() async {
            await midi.reconcileConnectedDevice(
              reason: 'resume',
              scanIfNeeded: true,
            );
            await connectionState.tryAutoReconnect(
              reason: MidiReconnectTrigger.resume,
            );
          }),
        );
        break;

      case AppLifecycleState.inactive:
        // Often transient (permission dialogs, app switcher). Avoid scan churn.
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        midi.setBackgrounded(true);
        connectionState.setBackgrounded(true);
        // Whatever the OS did with MIDI while suspended (buffered it,
        // dropped it, delivered it late) is unknowable, so the observation
        // ends here rather than pretending it continued. The link stays up:
        // keeping the transport connected is a separate decision.
        input.suspendObservation();
        // Fire-and-forget: best-effort scan stop is enough while
        // backgrounding.
        unawaited(connectionState.stopScanning());
        break;
    }
  }
}
