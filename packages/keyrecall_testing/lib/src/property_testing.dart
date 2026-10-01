import 'dart:io';

import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

/// Fixed so every run explores the same values; a failure names its seed.
const int propertySeed = 20260930;

/// [count] multiplied by `KEYRECALL_SEED_SCALE`, so a property checked on a
/// small budget every commit can be searched widely on demand.
///
/// Throws [ArgumentError] unless the scale is a positive integer, since zero
/// would check nothing and pass vacuously.
int propertyBudget(int count) {
  final value = Platform.environment['KEYRECALL_SEED_SCALE'];
  if (value == null) return count;
  final scale = int.tryParse(value);
  if (scale == null || scale < 1) {
    throw ArgumentError.value(
      value,
      'KEYRECALL_SEED_SCALE',
      'must be a positive integer',
    );
  }
  return count * scale;
}

/// [body], with any thrown [Error] reported as a failure.
///
/// kiri_check shrinks only what is thrown as an [Exception], so a crash would
/// otherwise surface unshrunk and without its seed.
void Function(T) failingOnErrors<T>(void Function(T) body) => (value) {
  try {
    body(value);
  } on Error catch (error, stackTrace) {
    fail('$error\n$stackTrace');
  }
};

/// One of [choices], picked in proportion to its weight.
Arbitrary<T> weighted<T>(List<(int, Arbitrary<T>)> choices) =>
    frequency(choices).map((value) => value as T);

/// [present], or null a quarter of the time.
Arbitrary<T?> optional<T>(Arbitrary<T> present) => weighted<T?>([
  (1, constant<T?>(null)),
  (3, present.map<T?>((value) => value)),
]);

/// One of [values].
Arbitrary<T> choiceOf<T>(List<T> values) => constantFrom(values);

/// What one property's generated examples reached, checked once they have all
/// run.
///
/// Give [check] to `forAll` as `tearDownAll` and [falsified] as `onFalsify`.
/// A property that fails reports that failure instead, since what its
/// shrinking left reached says nothing about the generator.
class Reached<V> {
  /// Every value the examples have to reach.
  final Set<V> expected;

  final Set<V> _seen = {};
  bool _falsified = false;

  Reached(this.expected);

  void add(V value) => _seen.add(value);

  void falsified(Object? example) => _falsified = true;

  void check() {
    if (_falsified) return;
    expect(
      expected.difference(_seen),
      isEmpty,
      reason: 'the generated examples never reached these',
    );
  }
}
