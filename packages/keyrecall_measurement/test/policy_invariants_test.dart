import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// The policy is a calibrated constant, so its invariants are assertions; see
/// `docs/domain-model/validation-boundaries.md`.
void main() {
  test('every scale reads between its ends', () {
    for (final build in [
      () => MeasurementPolicy(steadyDispersion: 0.9, unsteadyDispersion: 0.67),
      () => MeasurementPolicy(
        unbrokenIntervalRatio: 4.0,
        brokenIntervalRatio: 3.0,
      ),
      () => MeasurementPolicy(
        synchronizedAsynchronyMs: 200,
        uncoordinatedAsynchronyMs: 150,
      ),
    ]) {
      expect(build, throwsA(isA<AssertionError>()));
    }
  });

  test('the coordination tail carries a fraction of the score', () {
    expect(
      () => MeasurementPolicy(coordinationTailWeight: 1.5),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => MeasurementPolicy(coordinationTailWeight: -0.1),
      throwsA(isA<AssertionError>()),
    );
  });
}
