import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

/// What the live transport's clock looks like, whether or not a take is
/// running.
///
/// Watching before recording is the point: a take that lands on a domain
/// nobody expected is not discovered until the file is read, and one already
/// has.
///
/// The mapper's own reading, not a second detector's. An earlier version ran
/// its own over the transport records, which include the traffic the boundary
/// turned away, so the screen could name a shape nothing was timing against
/// while the adopted instrument's clock was something else.
final clockDomainProvider = Provider<LiveClockDomain>((ref) {
  final input = ref.watch(midiInputProvider);
  return (
    observation: input.clockObservation,
    phase: input.clockPhase,
    isObserving: input.isObserving,
  );
});

/// What was measured about the clock, and where its timeline stands.
///
/// Two questions, and the second is not the first. A shape is a property of
/// the domain the detector found; a phase is a property of this observation's
/// timeline, which can have failed under a shape that is perfectly well
/// authorized.
/// [isObserving] is the third: a suspended observation leaves the mapper's
/// last phase standing, and nothing is being timed while it does.
typedef LiveClockDomain = ({
  ClockDomainObservation observation,
  PerformanceClockPhase phase,
  bool isObserving,
});

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
  // The quantum, which is the clock's resolution. How fast the counter runs
  // is a different number, and on one characterized domain it is ten times
  // this one.
  final quantum = granularity == 1
      ? 'steps of 1 count'
      : 'steps of ${_grouped(granularity)} counts';
  final clock = policy.clockFor(observation.shape!);
  final rate = clock == null
      ? ''
      : ' at ${_grouped(clock.countsPerMillisecond)} counts/ms';
  final modulus = observation.modulus;
  return modulus == null ? '$quantum$rate' : '$quantum$rate, modulo $modulus';
}

/// What timing can be read from the clock right now.
///
/// A shape being authorized is not the same as a timeline being usable, so
/// this reports the phase where they disagree. Saying "performance" for a
/// failed timeline would report an authorization as an availability.
String clockTimingLabel(
  LiveClockDomain domain, {
  ClockDomainPolicy policy = ClockDomainPolicy.characterized,
}) {
  if (!domain.isObserving) return 'unavailable, nothing is being observed';
  final authorization = policy.classify(domain.observation);
  if (domain.phase == PerformanceClockPhase.failed) {
    return 'unavailable, the timeline failed';
  }
  if (authorization == ClockAuthorization.performance &&
      domain.phase != PerformanceClockPhase.active) {
    return 'not yet timing';
  }
  return clockAuthorizationLabel(authorization);
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
