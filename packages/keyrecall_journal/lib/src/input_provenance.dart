import 'package:meta/meta.dart';

import 'canonical_json.dart';

/// What an attempt was played on, as a class of input rather than a device.
///
/// Timing from different transports differs in resolution and jitter, and a
/// synthetic instrument is not somebody playing, so a reading that pools
/// attempts has to be able to tell them apart. Nothing here names an
/// instrument: no device identifier, no name, no connection.
@immutable
class InputProvenance {
  /// Which kind of source played it, as the app names it: `MIDI` or `DEMO`.
  final String source;

  /// How a MIDI instrument was attached, as its transport names it, such as
  /// `ble`, `usb`, or `network`, or null when there was none.
  final String? transport;

  /// The shape of the clock its notes were timed on, or null when none was
  /// read.
  final int? clockGranularity;
  final int? clockModulus;

  const InputProvenance({
    required this.source,
    this.transport,
    this.clockGranularity,
    this.clockModulus,
  });

  @override
  bool operator ==(Object other) =>
      other is InputProvenance &&
      other.source == source &&
      other.transport == transport &&
      other.clockGranularity == clockGranularity &&
      other.clockModulus == clockModulus;

  @override
  int get hashCode =>
      Object.hash(source, transport, clockGranularity, clockModulus);

  @override
  String toString() =>
      'InputProvenance($source, $transport, '
      'clock: $clockGranularity${clockModulus == null ? '' : ' mod $clockModulus'})';
}

Map<String, Object?> encodeInputProvenance(InputProvenance input) => {
  'source': input.source,
  'transport': input.transport,
  'clock_granularity': input.clockGranularity,
  'clock_modulus': input.clockModulus,
};

InputProvenance decodeInputProvenance(
  Map<String, Object?> json, {
  String? location,
}) => InputProvenance(
  source: requireString(json, 'source', location: location),
  transport: asOptionalString(
    json['transport'],
    'transport',
    location: location,
  ),
  clockGranularity: asOptionalInt(
    json['clock_granularity'],
    'clock_granularity',
    location: location,
  ),
  clockModulus: asOptionalInt(
    json['clock_modulus'],
    'clock_modulus',
    location: location,
  ),
);
