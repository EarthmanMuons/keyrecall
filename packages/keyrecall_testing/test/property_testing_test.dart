import 'package:test/test.dart';

import 'package:keyrecall_testing/keyrecall_testing.dart';

void main() {
  test('the budget is the count itself unless a scale is set', () {
    // The suite runs without KEYRECALL_SEED_SCALE; a wide run sets it for
    // every package at once.
    expect(propertyBudget(7), greaterThanOrEqualTo(7));
    expect(propertyBudget(7) % 7, 0);
  });
}
