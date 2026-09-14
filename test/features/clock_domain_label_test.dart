import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'package:keyrecall/features/practice/clock_domain.dart';

void main() {
  // The measuring and the trusting are tested in keyrecall_input. What is
  // left here is the wording, and one rule about it: the screen must never
  // show a shape that nothing is willing to classify.
  test('a shape is not named before the policy will name it', () {
    const observation = ClockDomainObservation(
      session: 'a',
      steps: 3,
      granularity: 1,
    );

    expect(clockDomainLabel(observation), 'detecting');
  });

  test('a named shape says what was measured and nothing else', () {
    expect(
      clockDomainLabel(
        const ClockDomainObservation(
          session: 'a',
          steps: 20,
          granularity: 1,
          modulus: 8192,
        ),
      ),
      'steps of 1 count at 1 counts/ms, modulo 8192',
    );
    expect(
      clockDomainLabel(
        const ClockDomainObservation(
          session: 'a',
          steps: 20,
          granularity: 1000000,
        ),
      ),
      'steps of 1,000,000 counts',
      reason: 'nothing authorized it, so there is no rate to report',
    );
  });

  // The step size is the clock's resolution and not how fast it runs. On the
  // network session they differ by a factor of ten, and the label said the
  // quantum was the rate.
  test('a step is not a rate', () {
    expect(
      clockDomainLabel(
        const ClockDomainObservation(
          session: 'a',
          steps: 20,
          granularity: 100000,
        ),
      ),
      'steps of 100,000 counts at 1,000,000 counts/ms',
    );
  });

  // An authorized shape is a property of the domain; a usable timeline is a
  // property of this observation. The screen reported the first as the second,
  // so a failed timeline still read as performance timing.
  group('timing availability is not shape authorization', () {
    const authorized = ClockDomainObservation(
      session: 'a',
      steps: 20,
      granularity: 1,
      modulus: 8192,
    );

    test('an active timeline on an authorized shape is timing', () {
      expect(
        clockTimingLabel((
          observation: authorized,
          phase: PerformanceClockPhase.active,
        )),
        'performance',
      );
    });

    test('a failed timeline is not, however good the shape is', () {
      expect(
        clockTimingLabel((
          observation: authorized,
          phase: PerformanceClockPhase.failed,
        )),
        'unavailable, the timeline failed',
      );
    });

    test('an authorized shape that has not anchored yet is not either', () {
      expect(
        clockTimingLabel((
          observation: authorized,
          phase: PerformanceClockPhase.detecting,
        )),
        'not yet timing',
      );
    });

    test('an unauthorized shape says what the policy says', () {
      expect(
        clockTimingLabel((
          observation: const ClockDomainObservation(
            session: 'a',
            steps: 20,
            granularity: 1000000,
          ),
          phase: PerformanceClockPhase.unauthorized,
        )),
        'not performance',
      );
    });
  });

  test('every authorization has words for it', () {
    for (final authorization in ClockAuthorization.values) {
      expect(clockAuthorizationLabel(authorization), isNotEmpty);
    }
  });
}
