import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/motion.dart';

void main() {
  group('preference', () {
    test('neither platform setting leaves motion full', () {
      final motion = Motion.fromFeatures(
        disableAnimations: false,
        reduceMotion: false,
      );

      expect(motion.reduced, isFalse);
    });

    test("Android's Remove animations reduces motion", () {
      final motion = Motion.fromFeatures(
        disableAnimations: true,
        reduceMotion: false,
      );

      expect(motion.reduced, isTrue);
    });

    test("iOS's Reduce Motion reduces motion on its own", () {
      final motion = Motion.fromFeatures(
        disableAnimations: false,
        reduceMotion: true,
      );

      expect(motion.reduced, isTrue);
    });
  });

  group('travel', () {
    const duration = Duration(milliseconds: 280);

    test('takes its time under full motion', () {
      expect(const Motion(reduced: false).travel(duration), duration);
    });

    test('arrives at once under reduced motion', () {
      expect(const Motion(reduced: true).travel(duration), Duration.zero);
    });
  });
}
