import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Draws recorded from CPython, which is what makes a Dart run comparable to a
/// reference run attempt by attempt:
///
/// ```python
/// import random
/// random.Random(0).random()
/// ```
void main() {
  group('matches the CPython random.Random stream', () {
    test('random()', () {
      final rng = PythonCompatibleRandom(0);
      expect(
        [for (var i = 0; i < 3; i++) rng.nextDouble()],
        [0.8444218515250481, 0.7579544029403025, 0.420571580830845],
      );
    });

    test('getrandbits()', () {
      final rng = PythonCompatibleRandom(7);
      expect([for (var i = 0; i < 5; i++) rng.nextBits(3)], [2, 7, 1, 3, 5]);
    });

    test('gauss()', () {
      final rng = PythonCompatibleRandom(11);
      expect(
        [for (var i = 0; i < 4; i++) rng.nextGaussian(0.0, 1.0)],
        [
          -1.224072675713965,
          0.3775881983015979,
          0.9949996276709397,
          -0.5132099485894354,
        ],
      );
    });

    test('choice()', () {
      final rng = PythonCompatibleRandom(2);
      expect(
        [
          for (var i = 0; i < 6; i++) rng.choice(const ['a', 'b', 'c']),
        ],
        ['a', 'a', 'a', 'b', 'a', 'c'],
      );
    });
  });

  group('basic properties', () {
    test('the same seed reproduces the same stream', () {
      final first = PythonCompatibleRandom(42);
      final second = PythonCompatibleRandom(42);
      for (var i = 0; i < 100; i++) {
        expect(first.nextDouble(), second.nextDouble());
      }
    });

    test('different seeds diverge', () {
      final first = PythonCompatibleRandom(1);
      final second = PythonCompatibleRandom(2);
      expect(first.nextDouble(), isNot(second.nextDouble()));
    });

    test('doubles stay in the unit interval', () {
      final rng = PythonCompatibleRandom(3);
      for (var i = 0; i < 2000; i++) {
        final value = rng.nextDouble();
        expect(value, greaterThanOrEqualTo(0.0));
        expect(value, lessThan(1.0));
      }
    });

    test('bounded integers cover their range and stay inside it', () {
      final rng = PythonCompatibleRandom(4);
      final seen = <int>{};
      for (var i = 0; i < 2000; i++) {
        final value = rng.nextIntBelow(5);
        expect(value, inInclusiveRange(0, 4));
        seen.add(value);
      }
      expect(seen, {0, 1, 2, 3, 4});
    });

    test('rejects arguments it cannot serve', () {
      final rng = PythonCompatibleRandom(5);
      expect(() => rng.nextIntBelow(0), throwsArgumentError);
      expect(() => rng.nextBits(33), throwsArgumentError);
      expect(() => rng.choice(const <int>[]), throwsArgumentError);
    });
  });
}
