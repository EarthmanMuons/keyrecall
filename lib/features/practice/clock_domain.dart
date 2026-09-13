import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

/// Whether a clock may contribute performance timing.
///
/// Recognizing what a count is worth does not by itself authorize a clock to
/// say when somebody played. The two questions are answered separately
/// because the answers have come apart: one domain carries onset timing that
/// delivery destroys, and another is recognized and carries nothing arrival
/// time does not already have.
enum ClockTimingUse {
  /// Not enough of the stream has been seen to say.
  detecting,

  /// Carries timing evidence about playing.
  performance,

  /// Understood, and not evidence about playing.
  nonPerformance,

  /// Nothing here has characterized this. Timing is unavailable.
  unavailable,
}

/// How many steps to see before naming a domain.
///
/// One step is a coincidence. The granularity is a common divisor, so a short
/// run can share a larger one by chance.
const int _minimumSteps = 8;

/// What a transport's timestamps look like, read off them rather than asked.
///
/// Characterization found the same adapter producing two different domains in
/// two sessions, with nothing reconnected between them. So a domain belongs to
/// the session and has to be measured every time, and this measures it: the
/// granularity every observed step is a multiple of, and the modulus if the
/// clock has been seen to wrap.
///
/// It names no origin. Calling a shape "the BLE clock" or "the host clock" is
/// how the last reading of this went wrong.
@immutable
class ClockDomainReading {
  /// The observation this was measured within.
  final String? session;

  /// How many steps between timestamps have been seen.
  final int steps;

  /// What every step so far is a multiple of, or null before any.
  final int? granularity;

  /// Where the clock was seen to wrap, or null if it has not.
  final int? modulus;

  /// The last timestamp and arrival seen, which is what a step is measured
  /// against.
  @visibleForTesting
  final int? lastTimestamp;

  @visibleForTesting
  final int? lastArrivalMs;

  const ClockDomainReading({
    this.session,
    this.steps = 0,
    this.granularity,
    this.modulus,
    this.lastTimestamp,
    this.lastArrivalMs,
  });

  /// Nothing observed yet.
  static const ClockDomainReading none = ClockDomainReading();

  /// This reading after one more delivery.
  ///
  /// A delivery from another session starts over, because that is the unit a
  /// domain belongs to.
  ClockDomainReading observing({
    required String? session,
    required int arrivalMs,
    int? timestamp,
  }) {
    if (session != this.session) {
      return ClockDomainReading(
        session: session,
        lastTimestamp: timestamp,
        lastArrivalMs: arrivalMs,
      );
    }
    final previous = lastTimestamp;
    final previousArrival = lastArrivalMs;
    if (timestamp == null || previous == null || previousArrival == null) {
      return ClockDomainReading(
        session: session,
        steps: steps,
        granularity: granularity,
        modulus: modulus,
        lastTimestamp: timestamp ?? previous,
        lastArrivalMs: arrivalMs,
      );
    }

    final step = timestamp - previous;
    final elapsed = arrivalMs - previousArrival;
    // A backward step is a wrap, and how far it went back plus how long it
    // took says how wide the counter is.
    final wrapped = step < 0 ? _nearestModulus(elapsed - step) : modulus;
    return ClockDomainReading(
      session: session,
      steps: steps + (step == 0 ? 0 : 1),
      granularity: step == 0 ? granularity : _gcd(granularity, step.abs()),
      modulus: wrapped,
      lastTimestamp: timestamp,
      lastArrivalMs: arrivalMs,
    );
  }

  /// What this domain may be used for.
  ///
  /// Every value rests on the takes in `analysis/transport-clocks/`, and on
  /// nothing else. A shape nobody has recorded is unavailable rather than
  /// assumed to behave like one that has been.
  ClockTimingUse get timingUse {
    if (steps < _minimumSteps || granularity == null) {
      return ClockTimingUse.detecting;
    }
    return switch (granularity!) {
      // A 1 ms counter modulo 8192, which preserves onsets delivery collapses.
      1 => ClockTimingUse.performance,
      // Seen once, over a network session, carrying the variation of playing
      // that the arrival clock on that path flattened away.
      100000 => ClockTimingUse.performance,
      // Recognized, and it has added nothing over arrival time on any take.
      1000000 => ClockTimingUse.nonPerformance,
      _ => ClockTimingUse.unavailable,
    };
  }

  /// The shape, said as what was measured.
  ///
  /// Silent until there is enough to name, so the screen never shows a shape
  /// this is unwilling to classify.
  String get label {
    if (granularity == null || steps < _minimumSteps) return 'detecting';
    final counts = granularity == 1
        ? '1 count/ms'
        : '${_grouped(granularity!)} counts/ms';
    return modulus == null ? counts : '$counts, modulo $modulus';
  }

  static int? _nearestModulus(int estimate) {
    const candidates = [8192, 16384, 32768, 65536];
    if (estimate <= 0) return null;
    var best = candidates.first;
    for (final candidate in candidates) {
      if ((candidate - estimate).abs() < (best - estimate).abs()) {
        best = candidate;
      }
    }
    // Several moduli can fit one long silence; take the one per wrap.
    while (best * 2 <= estimate) {
      best *= 2;
    }
    return best;
  }

  static int _gcd(int? a, int b) {
    var x = a ?? b;
    var y = b;
    while (y != 0) {
      (x, y) = (y, x % y);
    }
    return x;
  }

  static String _grouped(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}

/// What the live transport's clock looks like, whether or not a take is
/// running.
///
/// Watching before recording is the point: a take that lands on a domain
/// nobody expected is not discovered until the file is read, and one already
/// has.
final clockDomainProvider =
    NotifierProvider<ClockDomainNotifier, ClockDomainReading>(
      ClockDomainNotifier.new,
    );

class ClockDomainNotifier extends Notifier<ClockDomainReading> {
  StreamSubscription<MidiTransportRecord>? _watching;
  ClockDomainReading _reading = ClockDomainReading.none;
  bool _isBuilt = false;

  @override
  ClockDomainReading build() {
    _reading = ClockDomainReading.none;
    _isBuilt = false;
    _watching = ref
        .read(midiInputProvider.notifier)
        .transportRecords
        .listen(_record);
    ref.onDispose(() => unawaited(_watching?.cancel()));
    _isBuilt = true;
    return _reading;
  }

  void _record(MidiTransportRecord record) {
    if (record case MidiTransportDelivery(:final envelope)) {
      _reading = _reading.observing(
        session: envelope.source.sessionId,
        arrivalMs: envelope.arrivalTimestampMs,
        timestamp: envelope.transportTimestamp,
      );
      if (_isBuilt) state = _reading;
    }
  }
}
