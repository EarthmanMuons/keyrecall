import 'package:test/test.dart';

import 'package:keyrecall_testing/keyrecall_testing.dart';

void main() {
  test('the budget is the count itself unless a scale is set', () {
    // The suite runs without KEYRECALL_SEED_SCALE; a wide run sets it for
    // every package at once.
    expect(propertyBudget(7), greaterThanOrEqualTo(7));
    expect(propertyBudget(7) % 7, 0);
  });

  group('what generated examples reached', () {
    test('fails on a value never reached', () {
      final reached = Reached({1, 2})..add(1);
      expect(reached.check, throwsA(isA<TestFailure>()));
    });

    test('passes once every value is reached', () {
      final reached = Reached({1, 2})
        ..add(2)
        ..add(1)
        ..add(3);
      reached.check();
    });

    test('stands aside for a property that failed', () {
      final reached = Reached({1})..falsified(0);
      reached.check();
    });
  });
}
