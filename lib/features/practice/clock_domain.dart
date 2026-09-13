import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

/// What the live transport's clock looks like, whether or not a take is
/// running.
///
/// Watching before recording is the point: a take that lands on a domain
/// nobody expected is not discovered until the file is read, and one already
/// has. The measuring and the trusting both live in `keyrecall_input`; this is
/// the wiring and the wording.
final clockDomainProvider =
    NotifierProvider<ClockDomainNotifier, ClockDomainObservation>(
      ClockDomainNotifier.new,
    );

class ClockDomainNotifier extends Notifier<ClockDomainObservation> {
  final ClockDomainDetector _detector = ClockDomainDetector();
  StreamSubscription<MidiTransportRecord>? _watching;
  bool _isBuilt = false;

  @override
  ClockDomainObservation build() {
    _isBuilt = false;
    _watching = ref
        .read(midiInputProvider.notifier)
        .transportRecords
        .listen(_record);
    ref.onDispose(() => unawaited(_watching?.cancel()));
    _isBuilt = true;
    return _detector.observation;
  }

  void _record(MidiTransportRecord record) {
    if (record case MidiTransportDelivery(:final envelope)) {
      final observation = _detector.observe(
        session: envelope.source.sessionId,
        arrivalMs: envelope.arrivalTimestampMs,
        timestamp: envelope.transportTimestamp,
      );
      if (_isBuilt) state = observation;
    }
  }
}

/// The measured shape, for somebody reading it off a phone.
///
/// Silent until the policy will name it, so the screen never shows a shape
/// nothing is willing to classify.
String clockDomainLabel(
  ClockDomainObservation observation, {
  ClockDomainPolicy policy = ClockDomainPolicy.characterized,
}) {
  final granularity = observation.granularity;
  if (granularity == null ||
      policy.classify(observation) == ClockAuthorization.detecting) {
    return 'detecting';
  }
  final counts = granularity == 1
      ? '1 count/ms'
      : '${_grouped(granularity)} counts/ms';
  final modulus = observation.modulus;
  return modulus == null ? counts : '$counts, modulo $modulus';
}

/// What that shape is allowed to say about playing.
String clockAuthorizationLabel(ClockAuthorization authorization) =>
    switch (authorization) {
      ClockAuthorization.detecting => 'not yet known',
      ClockAuthorization.performance => 'performance',
      ClockAuthorization.nonPerformance => 'not performance',
      ClockAuthorization.unavailable =>
        'unavailable, nothing has characterized it',
    };

String _grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
