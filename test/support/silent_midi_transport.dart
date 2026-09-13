import 'dart:async';

import 'package:keyrecall_midi/keyrecall_midi.dart';

/// A MIDI transport that exists and does nothing, for a test with no radio.
///
/// Anything reading the input boundary builds the real plugin otherwise, which
/// opens Bluetooth and leaves timers running past the end of the test. This
/// answers every question with nothing rather than pretending to be an
/// instrument: a test that wants notes drives the synthetic source instead.
final silentMidiTransport = midiBleServiceProvider.overrideWithValue(
  _SilentMidiTransport(),
);

class _SilentMidiTransport implements MidiBleService {
  @override
  Stream<BluetoothState> get onBluetoothStateChanged => const Stream.empty();

  @override
  Stream<void> get onMidiSetupChanged => const Stream.empty();

  @override
  Stream<MidiSourceMessage> get onMidiMessages => const Stream.empty();

  @override
  BluetoothState get bluetoothState => BluetoothState.poweredOff;

  @override
  Future<void> startCentral({Duration timeout = Duration.zero}) async {}

  @override
  Future<void> waitUntilInitialized({Duration timeout = Duration.zero}) async {}

  @override
  Future<void> ensureCentralReady({Duration timeout = Duration.zero}) async {}

  @override
  Future<void> startScanning({Duration timeout = Duration.zero}) async {}

  @override
  Future<void> stopScanning() async {}

  @override
  Future<List<MidiDevice>> devices() async => const [];

  @override
  Future<void> connect(
    String deviceId, {
    Duration timeout = Duration.zero,
  }) async {}

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<bool> isConnected(String deviceId) async => false;
}
