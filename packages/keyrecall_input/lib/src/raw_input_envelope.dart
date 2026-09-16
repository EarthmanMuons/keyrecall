import 'package:meta/meta.dart';

import 'clock_domain.dart';

/// Which instrument, over which transport, on which connection.
///
/// Identity is what lets the boundary tell the adopted instrument from any
/// other live source. [sessionId] distinguishes two connections to the same
/// physical device, because a reconnect is a new observation even though the
/// device id did not change.
@immutable
class InputSourceIdentity {
  /// The transport's own identifier for the device.
  final String deviceId;

  /// How it is attached, as the transport names it.
  final String transport;

  /// Which connection to that device, when the transport can tell.
  final String? sessionId;

  const InputSourceIdentity({
    required this.deviceId,
    required this.transport,
    this.sessionId,
  });

  @override
  bool operator ==(Object other) =>
      other is InputSourceIdentity &&
      other.deviceId == deviceId &&
      other.transport == transport &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(deviceId, transport, sessionId);

  @override
  String toString() =>
      'InputSourceIdentity($transport:$deviceId'
      '${sessionId == null ? '' : '#$sessionId'})';
}

/// What a raw message is trying to say, before anything believes it.
///
/// Transport-specific spellings are already resolved: a MIDI adapter decides
/// that CC 64 is [sustain] and that CC 120 and 123 are both [allNotesOff], so
/// nothing downstream reasons about controller numbers.
enum RawInputKind {
  noteOn,
  noteOff,
  sustain,
  allNotesOff,

  /// Something the instrument sent that KeyRecall does not consume.
  other,
}

/// One raw message, with its fields unvalidated.
///
/// The fields are nullable and unchecked on purpose. A payload that cannot be
/// believed has to survive as far as the reducer, which rejects it explicitly
/// rather than clamping it into a note somebody could have played.
@immutable
class RawInputMessage {
  final RawInputKind kind;
  final int? note;
  final int? velocity;

  /// How far the pedal is down, on the transport's scale.
  final int? sustainValue;

  const RawInputMessage({
    required this.kind,
    this.note,
    this.velocity,
    this.sustainValue,
  });

  @override
  String toString() => switch (kind) {
    RawInputKind.noteOn ||
    RawInputKind.noteOff => '${kind.name}(note: $note, velocity: $velocity)',
    RawInputKind.sustain => 'sustain($sustainValue)',
    RawInputKind.allNotesOff => 'allNotesOff',
    RawInputKind.other => 'other',
  };
}

/// Which path stamped a transport timestamp, and what it documents.
///
/// A device and its reported transport do not identify a clock: one adapter
/// has delivered two different domains by two different paths through the
/// same plugin. The path does, so a change of path is a new clock rather than
/// a discontinuity in the old one.
@immutable
class TimestampSource {
  /// Names the path, such as the decoder or operating system stack that
  /// produced the stamp.
  final String path;

  /// The shape the path's format defines, where it defines one.
  ///
  /// A declaration identifies a clock without waiting for the stream to show
  /// it, which for a wrapping counter means waiting for a wrap. It does not
  /// authorize anything: policy still decides whether the shape is believed,
  /// and a stream that contradicts it is measured rather than trusted.
  final ClockDomainShape? declaredShape;

  const TimestampSource({required this.path, this.declaredShape});

  @override
  bool operator ==(Object other) =>
      other is TimestampSource &&
      other.path == path &&
      other.declaredShape == declaredShape;

  @override
  int get hashCode => Object.hash(path, declaredShape);

  @override
  String toString() =>
      'TimestampSource($path'
      '${declaredShape == null ? '' : ', declares $declaredShape'})';
}

/// A raw message with everything known about where and when it arrived.
///
/// Two clocks, deliberately kept apart. [arrivalTimestampMs] is the app's
/// monotonic clock reading taken when the message was processed, which orders
/// the stream and nothing more. [transportTimestamp] is the transport's own
/// stamp, in the transport's clock domain, which may wrap and is not
/// comparable across sources. Nothing yet converts one into the other.
@immutable
class RawInputEnvelope {
  final InputSourceIdentity source;

  /// The MIDI channel the message arrived on, where the transport reports one.
  final int? channel;

  final RawInputMessage message;

  /// The transport's own timestamp, uninterpreted.
  final int? transportTimestamp;

  /// Where [transportTimestamp] came from, where the transport can say.
  final TimestampSource? timestampSource;

  /// The shared input clock's reading when this message was processed.
  final int arrivalTimestampMs;

  const RawInputEnvelope({
    required this.source,
    required this.message,
    required this.arrivalTimestampMs,
    this.channel,
    this.transportTimestamp,
    this.timestampSource,
  });

  @override
  String toString() =>
      'RawInputEnvelope($message from $source'
      '${channel == null ? '' : ' ch$channel'} at ${arrivalTimestampMs}ms)';
}
