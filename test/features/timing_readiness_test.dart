import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'package:keyrecall/features/input/input.dart';

void main() {
  TimingReadiness? midi(
    PerformanceClockPhase phase, {
    bool isObserving = true,
  }) => timingReadinessOf(
    source: InputSourceKind.midi,
    isObserving: isObserving,
    phase: phase,
  );

  test('readiness follows the clock that will time the attempt', () {
    expect(midi(PerformanceClockPhase.detecting), TimingReadiness.establishing);
    expect(midi(PerformanceClockPhase.active), TimingReadiness.ready);
    expect(
      midi(PerformanceClockPhase.unauthorized),
      TimingReadiness.unavailable,
    );
    expect(midi(PerformanceClockPhase.failed), TimingReadiness.failed);
  });

  test('nothing is said about timing nobody is observing or needs', () {
    expect(midi(PerformanceClockPhase.failed, isObserving: false), isNull);
    expect(
      timingReadinessOf(
        source: InputSourceKind.demo,
        isObserving: true,
        phase: PerformanceClockPhase.detecting,
      ),
      isNull,
    );
  });
}
