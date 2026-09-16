import 'package:flutter/foundation.dart';

import 'midi_device.dart';
import 'midi_message.dart';

/// Which of the plugin's routes carried a message.
///
/// The operating system's own MIDI stack and the app's injected BLE transport
/// both deliver BLE instruments, and they do not stamp them from the same
/// clock.
enum MidiRoute { host, ble, network, virtual, unknown }

/// A MIDI message with everything known about where and when it came from.
///
/// The plugin merges every live source into one stream, so a message that has
/// lost its device is indistinguishable from one another instrument sent.
/// Provenance survives as far as the admission filter, which is the only place
/// allowed to decide a message belongs to the adopted instrument.
@immutable
class MidiSourceMessage {
  final MidiMessage message;

  /// The transport's identifier for the instrument that sent it.
  final String deviceId;

  /// How that instrument describes itself.
  final MidiTransportType transport;

  /// Which of the plugin's routes actually delivered it.
  ///
  /// Not the same question as [transport], and the difference matters: a BLE
  /// instrument the operating system has paired into its own MIDI stack
  /// arrives by the host route, while one the app's own BLE transport is
  /// talking to arrives by the BLE route. They carry timestamps from
  /// different clocks, so nothing may read [transportTimestamp] without
  /// knowing which route it came by.
  final MidiRoute route;

  /// The plugin's own timestamp, in the clock domain of [route].
  ///
  /// Kept, not interpreted here. The BLE route carries the BLE MIDI packet
  /// timestamp, a millisecond counter modulo 8192, and the host route carries
  /// the operating system's own stamp.
  final int transportTimestamp;

  const MidiSourceMessage({
    required this.message,
    required this.deviceId,
    required this.transport,
    required this.transportTimestamp,
    this.route = MidiRoute.unknown,
  });

  @override
  String toString() =>
      '$message from $deviceId (${transport.name} by ${route.name})';
}
