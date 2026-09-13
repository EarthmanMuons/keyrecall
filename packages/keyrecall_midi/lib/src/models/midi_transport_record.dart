import 'package:flutter/foundation.dart';

import 'package:keyrecall_input/keyrecall_input.dart';

import 'midi_source_message.dart';

/// Why the observation changed hands.
enum MidiTransportBoundaryKind {
  /// A transport subscription was opened, and with it an observation.
  sessionOpened,

  /// An integrity fault closed the observation.
  observationFailed,

  /// A consumer attached and was handed where things stood.
  consumerAttached,
}

/// One thing the transport did, recorded before anything decided what it meant.
///
/// For characterizing transports rather than for running on. Deliveries are
/// taken at the raw boundary, ahead of admission and normalization, because a
/// message that was rejected, stale, or malformed is exactly the one that
/// might explain a discontinuity in the ones that were not.
///
/// Nothing here influences what the boundary does with the same message.
@immutable
sealed class MidiTransportRecord {
  /// Where this sits in the capture, from zero.
  final int sequence;

  /// The shared input clock when it was recorded.
  final int arrivalTimestampMs;

  const MidiTransportRecord({
    required this.sequence,
    required this.arrivalTimestampMs,
  });
}

/// A message the transport delivered.
final class MidiTransportDelivery extends MidiTransportRecord {
  /// Everything the reducer was shown, both clocks included.
  final RawInputEnvelope envelope;

  /// What the transport actually said, including the route that carried it.
  ///
  /// The envelope collapses everything KeyRecall does not consume into one
  /// kind with no payload, which is the right shape for a reducer and the
  /// wrong shape for characterization: half the messages an instrument sends
  /// would be unidentifiable in the trace that has to explain it.
  final MidiSourceMessage source;

  /// Whether the subscription that delivered it was still the live one.
  final bool live;

  const MidiTransportDelivery({
    required super.sequence,
    required super.arrivalTimestampMs,
    required this.envelope,
    required this.source,
    required this.live,
  });
}

/// A boundary in the observation, which no message need have crossed.
///
/// Recorded because the interesting ones are invisible otherwise: an app
/// backgrounded with nobody playing produces no deliveries at all, and a
/// discontinuity in the clocks either side of it would have nothing to be
/// attributed to.
final class MidiTransportBoundary extends MidiTransportRecord {
  final MidiTransportBoundaryKind kind;

  /// The transport session this boundary opened, where it opened one.
  final String? session;

  /// What input was being admitted from, at the boundary.
  final InputSourceIdentity? adopted;

  /// What closed the observation, where something did.
  final InputIntegrityFault? fault;

  /// Diagnostic detail, never parsed.
  final String? detail;

  const MidiTransportBoundary({
    required super.sequence,
    required super.arrivalTimestampMs,
    required this.kind,
    this.session,
    this.adopted,
    this.fault,
    this.detail,
  });
}
