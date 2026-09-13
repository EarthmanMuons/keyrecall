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
      '1 count/ms, modulo 8192',
    );
    expect(
      clockDomainLabel(
        const ClockDomainObservation(
          session: 'a',
          steps: 20,
          granularity: 1000000,
        ),
      ),
      '1,000,000 counts/ms',
    );
  });

  test('every authorization has words for it', () {
    for (final authorization in ClockAuthorization.values) {
      expect(clockAuthorizationLabel(authorization), isNotEmpty);
    }
  });
}
