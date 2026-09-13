import 'package:flutter/foundation.dart';

import 'midi_device.dart';
import 'midi_message.dart';

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

  /// How that instrument is attached.
  final MidiTransportType transport;

  /// The plugin's own timestamp, in the transport's clock domain.
  ///
  /// Kept, not interpreted. BLE stamps wrap and the clock domains differ
  /// between transports, so turning this into performance timing needs a
  /// conversion layer that does not exist yet.
  final int transportTimestamp;

  const MidiSourceMessage({
    required this.message,
    required this.deviceId,
    required this.transport,
    required this.transportTimestamp,
  });

  @override
  String toString() => '$message from $deviceId (${transport.name})';
}
