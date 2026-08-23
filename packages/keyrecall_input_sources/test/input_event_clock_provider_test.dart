import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall_input_sources/keyrecall_input_sources.dart';

void main() {
  test('every source in a scope reads the same clock', () {
    // Two sources on two clocks could not have their events ordered against
    // each other, which is the reason this provider exists.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(inputEventClockProvider),
      same(container.read(inputEventClockProvider)),
    );
  });

  test('the clock runs forward', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final clock = container.read(inputEventClockProvider);

    var previous = clock();
    for (var i = 0; i < 1000; i++) {
      final now = clock();
      expect(now, greaterThanOrEqualTo(previous));
      previous = now;
    }
  });

  test('separate scopes keep separate clocks', () {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    final second = ProviderContainer();
    addTearDown(second.dispose);

    expect(
      first.read(inputEventClockProvider),
      isNot(same(second.read(inputEventClockProvider))),
    );
  });
}
